// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { MarketParamsLib } from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { IMetaMorphoLike, IMorphoLike, Id, Market, MarketParams } from "../interfaces/Morpho.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract ERC4626_DonationAttack_TestBase is ForkTestBase {

    IMetaMorphoLike internal constant MORPHO_VAULT = IMetaMorphoLike(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    address internal morpho;

    MarketParams internal marketParams = MarketParams({
        loanToken       : Ethereum.USDS,
        collateralToken : address(0x0),
        oracle          : address(0x0),
        irm             : address(0x0),
        lltv            : 0
    });

    Id internal marketId = MarketParamsLib.id(marketParams);

    address internal curator       = makeAddr("curator");
    address internal guardian      = makeAddr("guardian");
    address internal feeRecipient  = makeAddr("feeRecipient");
    address internal allocator     = makeAddr("allocator");
    address internal skimRecipient = makeAddr("skimRecipient");

    address internal attacker = makeAddr("attacker");

    function setUp() override public {
        super.setUp();

        morpho = MORPHO_VAULT.MORPHO();

        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  address(MORPHO_VAULT));
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), address(MORPHO_VAULT));

        // Basic validation
        assertEq(keccak256(abi.encode(MORPHO_VAULT.symbol())), keccak256(abi.encode("sparkUSDS")));
        assertEq(MORPHO_VAULT.totalAssets(),                   0);
        assertEq(MORPHO_VAULT.totalSupply(),                   0);

        // Initialization
        vm.startPrank(Ethereum.SPARK_PROXY);

        MORPHO_VAULT.setCurator(curator);
        MORPHO_VAULT.submitGuardian(guardian);
        MORPHO_VAULT.setFeeRecipient(feeRecipient);
        MORPHO_VAULT.setIsAllocator(allocator, true);
        MORPHO_VAULT.setSkimRecipient(skimRecipient);

        MORPHO_VAULT.submitCap(marketParams, 10_000_000e18);
        skip(MORPHO_VAULT.timelock());  // Wait the timelock
        MORPHO_VAULT.acceptCap(marketParams);

        // Now that the market has a non-zero cap, set the supply queue order
        Id[] memory supplyOrder = new Id[](1);
        supplyOrder[0] = marketId;
        MORPHO_VAULT.setSupplyQueue(supplyOrder);

        vm.stopPrank();

        assertEq(MORPHO_VAULT.curator(),      curator);
        assertEq(MORPHO_VAULT.guardian(),     guardian);
        assertEq(MORPHO_VAULT.feeRecipient(), feeRecipient);

        assertTrue(MORPHO_VAULT.isAllocator(allocator));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 22932160;  // July 16, 2025
    }

}

contract MainnetController_ERC4626_DonationAttack_Tests is ERC4626_DonationAttack_TestBase {

    function test_depositERC4626_donationAttackFailure() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(MORPHO_VAULT), 1e18, 10e18);
        vm.stopPrank();

        _doAttack();

        vm.prank(relayer);
        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        mainnetController.depositERC4626(address(MORPHO_VAULT), 2_000_000e18, 0);
    }

    function test_depositERC4626_donationAttackSuccess() external {
        // Set max exchange rate too high
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(MORPHO_VAULT), 1, MORPHO_VAULT.convertToAssets(1e24));
        vm.stopPrank();

        _doAttack();

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(address(MORPHO_VAULT), 2_000_000e18, 0);

        // One can compute:
        // shares == assets * (totalSupply + 1) / (totalAssets + 1)
        //        == 2_000_000e18 * (1 + 1) / (1_000_000e18 + 1 + 1)
        //        == 3.9..
        // Rounding down, the proxy receives 3 shares.
        assertEq(shares,                    3);
        assertEq(MORPHO_VAULT.totalAssets(), 3_000_000e18 + 1);
        assertEq(MORPHO_VAULT.totalSupply(), 4);

        uint256 assetsOfProxy    = MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(address(almProxy)));
        uint256 assetsOfAttacker = MORPHO_VAULT.convertToAssets(MORPHO_VAULT.balanceOf(attacker));

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
        Market memory market = IMorphoLike(morpho).market(marketId);

        assertEq(market.totalSupplyAssets, 36_095_481.319542091092211965e18); // ~36M USDS
        assertEq(market.totalSupplyShares, 36_095_481.319542091092211965000000e24);

        deal(address(usds), attacker, 1_000_000e18 + 1);

        vm.startPrank(attacker);

        usds.approve(address(MORPHO_VAULT), 1);
        MORPHO_VAULT.deposit(1, attacker);
        usds.approve(morpho, 1_000_000e18);

        // Donation attack performed by donating shares of Morpho market supply to Morpho vault
        ( uint256 assets, uint256 shares ) = IMorphoLike(morpho).supply(
            marketParams, 1_000_000e18, 0, address(MORPHO_VAULT), hex""
        );

        vm.stopPrank();

        assertEq(assets, 1_000_000e18);
        assertEq(shares, uint256(1_000_000e18) * market.totalSupplyShares / market.totalSupplyAssets);
        assertEq(shares, 1e30);

        assertEq(MORPHO_VAULT.balanceOf(attacker), 1);
        assertEq(MORPHO_VAULT.totalSupply(),       1);

        assertEq(MORPHO_VAULT.totalAssets(), 1_000_000e18 + 1);
        // Instead of performing shares * totalAssets / totalShares, aka
        // 1 * (1_000_000e18 + 1) / 1 == 1_000_000e18 + 1, the vault actually adds 1 to the
        // numerator and denominator, so one gets 1 * (1_000_000e18 + 1 + 1) / (1 + 1)
        // == (1_000_000e18 + 2) / 2 == 500_000e18 + 1.
        assertEq(MORPHO_VAULT.convertToAssets(1), 500_000e18 + 1);

        deal(address(usds), address(almProxy), 2_000_000e18);
    }

}
