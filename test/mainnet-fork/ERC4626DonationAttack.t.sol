// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }               from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams, Market } from "morpho-blue/src/interfaces/IMorpho.sol";

import "./ForkTestBase.t.sol";

contract ERC4626DonationAttackTestBase is ForkTestBase {

    IMetaMorpho morpho_vault = IMetaMorpho(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    IMorpho morpho;

    MarketParams marketParams = MarketParams({
        loanToken: Ethereum.USDS,
        collateralToken: address(0x0),
        oracle: address(0x0),
        irm: address(0x0),
        lltv: 0
    });
    Id marketId = MarketParamsLib.id(marketParams);

    address curator        = makeAddr("curator");
    address guardian       = makeAddr("guardian");
    address fee_recipient  = makeAddr("fee_recipient");
    address allocator      = makeAddr("allocator");
    address skim_recipient = makeAddr("skim_recipient");

    function setUp() override public {
        super.setUp();

        morpho = morpho_vault.MORPHO();

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  address(morpho_vault));
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), address(morpho_vault));

        // Basic validation
        assertEq(keccak256(abi.encode(morpho_vault.symbol())), keccak256(abi.encode("sparkUSDS")));
        assertEq(morpho_vault.totalAssets(),                   0);
        assertEq(morpho_vault.totalSupply(),                   0);

        // Initialization
        vm.startPrank(Ethereum.SPARK_PROXY);
        morpho_vault.setCurator(curator);
        morpho_vault.submitGuardian(guardian);
        morpho_vault.setFeeRecipient(fee_recipient);
        morpho_vault.setIsAllocator(allocator, true);
        morpho_vault.setSkimRecipient(skim_recipient);

        morpho_vault.submitCap(marketParams, 10_000_000e18);
        skip(morpho_vault.timelock());  // Wait the timelock
        morpho_vault.acceptCap(marketParams);

        // Now that the market has a non-zero cap, set the supply queue order
        Id[] memory supplyOrder = new Id[](1);
        supplyOrder[0] = marketId;
        morpho_vault.setSupplyQueue(supplyOrder);
        vm.stopPrank();

        assertEq(morpho_vault.curator(),      curator);
        assertEq(morpho_vault.guardian(),     guardian);
        assertEq(morpho_vault.feeRecipient(), fee_recipient);
        assertTrue(morpho_vault.isAllocator(allocator));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.setMaxSlippage(address(morpho_vault), 1e18 - 1e4);  // Rounding slippage
        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 22932160;  // July 16, 2025
    }

}

contract ERC4626DonationAttack is ERC4626DonationAttackTestBase {

    function test_donationAttackERC4626_usds() external {
        address mallory = makeAddr("mallory");

        Market memory market = morpho.market(marketId);
        assertEq(market.totalSupplyAssets, 36_095_481.319542091092211965e18); // ~36M USDS
        assertEq(market.totalSupplyShares, 36_095_481.319542091092211965000000e24);

        deal(address(usds), mallory, 1_000_000e18 + 1);

        vm.startPrank(mallory);
        usds.approve(address(morpho_vault), 1);
        morpho_vault.deposit(1, mallory);
        usds.approve(address(morpho), 1_000_000e18);
        // Donation attack
        (uint256 assets, uint256 shares) = morpho.supply(
            marketParams, 1_000_000e18, 0, address(morpho_vault), hex""
        );
        vm.stopPrank();

        assertEq(assets, 1_000_000e18);
        assertEq(shares, uint256(1_000_000e18) * market.totalSupplyShares / market.totalSupplyAssets);
        assertEq(shares, 1e30);

        assertEq(morpho_vault.balanceOf(mallory), 1);
        assertEq(morpho_vault.totalSupply(), 1);

        assertEq(morpho_vault.totalAssets(), 1_000_000e18 + 1);
        // Instead of performing shares * totalAssets / totalShares, aka
        // 1 * (1_000_000e18 + 1) / 1 == 1_000_000e18 + 1, the vault actually adds 1 to the
        // numerator and denominator, so we get 1 * (1_000_000e18 + 1 + 1) / (1 + 1)
        // == (1_000_000e18 + 2) / 2 == 500_000e18 + 1.
        assertEq(morpho_vault.convertToAssets(1), 500_000e18 + 1);

        deal(address(usds), address(almProxy), 2_000_000e18);

        vm.prank(relayer);
        try mainnetController.depositERC4626(address(morpho_vault), 2_000_000e18) {
            // The deposit went through. The only time this is permissible is if the attack had no
            // effect.
            uint256 assetsOfProxy = morpho_vault.convertToAssets(morpho_vault.balanceOf(address(almProxy)));
            assertEq(assetsOfProxy,                             2_000_000e18);
            assertEq(morpho_vault.balanceOf(address(almProxy)), 2_000_000e24);
        } catch Error(string memory reason) {
            // The deposit was correctly reverted.
            assertEq(reason, "MainnetController/slippage-too-high");
        }
    }

}

