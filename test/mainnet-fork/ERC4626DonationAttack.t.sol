// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }               from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams, Market } from "morpho-blue/src/interfaces/IMorpho.sol";

import "./ForkTestBase.t.sol";

contract ERC4626DonationAttackTestBase is ForkTestBase {

    IMetaMorpho morphoVault = IMetaMorpho(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    IMorpho morpho;

    MarketParams marketParams = MarketParams({
        loanToken: Ethereum.USDS,
        collateralToken: address(0x0),
        oracle: address(0x0),
        irm: address(0x0),
        lltv: 0
    });
    Id marketId = MarketParamsLib.id(marketParams);

    address curator       = makeAddr("curator");
    address guardian      = makeAddr("guardian");
    address feeRecipient  = makeAddr("feeRecipient");
    address allocator     = makeAddr("allocator");
    address skimRecipient = makeAddr("skimRecipient");

    address attacker = makeAddr("attacker");

    function setUp() override public {
        super.setUp();

        morpho = morphoVault.MORPHO();

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  address(morphoVault));
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), address(morphoVault));

        // Basic validation
        assertEq(keccak256(abi.encode(morphoVault.symbol())), keccak256(abi.encode("sparkUSDS")));
        assertEq(morphoVault.totalAssets(),                   0);
        assertEq(morphoVault.totalSupply(),                   0);

        // Initialization
        vm.startPrank(Ethereum.SPARK_PROXY);

        morphoVault.setCurator(curator);
        morphoVault.submitGuardian(guardian);
        morphoVault.setFeeRecipient(feeRecipient);
        morphoVault.setIsAllocator(allocator, true);
        morphoVault.setSkimRecipient(skimRecipient);

        morphoVault.submitCap(marketParams, 10_000_000e18);
        skip(morphoVault.timelock());  // Wait the timelock
        morphoVault.acceptCap(marketParams);

        // Now that the market has a non-zero cap, set the supply queue order
        Id[] memory supplyOrder = new Id[](1);
        supplyOrder[0] = marketId;
        morphoVault.setSupplyQueue(supplyOrder);

        vm.stopPrank();

        assertEq(morphoVault.curator(),      curator);
        assertEq(morphoVault.guardian(),     guardian);
        assertEq(morphoVault.feeRecipient(), feeRecipient);

        assertTrue(morphoVault.isAllocator(allocator));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 22932160;  // July 16, 2025
    }

}

contract ERC4626DonationAttack is ERC4626DonationAttackTestBase {

    function test_depositERC4626_donationAttackFailure() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(morphoVault), 1e18, morphoVault.convertToAssets(1.2e18));
        vm.stopPrank();

        _doAttack();

        vm.prank(relayer);
        vm.expectRevert("MC/exchange-rate-too-high");
        mainnetController.depositERC4626(address(morphoVault), 2_000_000e18);
    }

    function test_depositERC4626_donationAttackSuccess() external {
        // Set max exchange rate too high
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(morphoVault), 1, morphoVault.convertToAssets(1e24));
        vm.stopPrank();

        _doAttack();

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(address(morphoVault), 2_000_000e18);

        // One can compute:
        // shares == assets * (totalSupply + 1) / (totalAssets + 1)
        //        == 2_000_000e18 * (1 + 1) / (1_000_000e18 + 1 + 1)
        //        == 3.9..
        // Rounding down, the proxy receives 3 shares.
        assertEq(shares,                    3);
        assertEq(morphoVault.totalAssets(), 3_000_000e18 + 1);
        assertEq(morphoVault.totalSupply(), 4);

        uint256 assetsOfProxy    = morphoVault.convertToAssets(morphoVault.balanceOf(address(almProxy)));
        uint256 assetsOfAttacker = morphoVault.convertToAssets(morphoVault.balanceOf(attacker));

        // convertToAssets(shares) == shares * (totalAssets + 1) / (totalSupply + 1)
        // convertToAssets(3)      == 3 * (3_000_000e18 + 1 + 1) / (4 + 1)
        //                         == 1_800_000e18 + 1
        assertEq(assetsOfProxy, 1_800_000e18 + 1);
        assertLt(assetsOfProxy, 2_000_000e18);  // The proxy owns less than it deposited
        // convertToAssets(1)      == 1 * (3_000_000e18 + 1 + 1) / (4 + 1)
        //                         == 600_000e18
        assertEq(assetsOfAttacker, 600_000e18);
    }

    function _doAttack() internal {
        Market memory market = morpho.market(marketId);

        assertEq(market.totalSupplyAssets, 36_095_481.319542091092211965e18); // ~36M USDS
        assertEq(market.totalSupplyShares, 36_095_481.319542091092211965000000e24);

        deal(address(usds), attacker, 1_000_000e18 + 1);

        vm.startPrank(attacker);
        usds.approve(address(morphoVault), 1);
        morphoVault.deposit(1, attacker);
        usds.approve(address(morpho), 1_000_000e18);

        // Donation attack performed by donating shares of Morpho market supply to Morpho vault
        (uint256 assets, uint256 shares) = morpho.supply(
            marketParams, 1_000_000e18, 0, address(morphoVault), hex""
        );
        vm.stopPrank();

        assertEq(assets, 1_000_000e18);
        assertEq(shares, uint256(1_000_000e18) * market.totalSupplyShares / market.totalSupplyAssets);
        assertEq(shares, 1e30);

        assertEq(morphoVault.balanceOf(attacker), 1);
        assertEq(morphoVault.totalSupply(),       1);

        assertEq(morphoVault.totalAssets(), 1_000_000e18 + 1);
        // Instead of performing shares * totalAssets / totalShares, aka
        // 1 * (1_000_000e18 + 1) / 1 == 1_000_000e18 + 1, the vault actually adds 1 to the
        // numerator and denominator, so one gets 1 * (1_000_000e18 + 1 + 1) / (1 + 1)
        // == (1_000_000e18 + 2) / 2 == 500_000e18 + 1.
        assertEq(morphoVault.convertToAssets(1), 500_000e18 + 1);

        deal(address(usds), address(almProxy), 2_000_000e18);
    }

}
