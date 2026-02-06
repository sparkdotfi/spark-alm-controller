// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 }   from "../../lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../lib/forge-std/src/interfaces/IERC4626.sol";

import { IMetaMorpho, Id } from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "../../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract Morpho_TestBase is ForkTestBase {

    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address constant MORPHO_VAULT_USDS = 0x0fFDeCe791C5a2cb947F8ddBab489E5C02c6d4F7;
    address constant MORPHO_VAULT_USDC = 0x305E03Ed9ADaAB22F4A58c24515D79f2B1E2FD5D;

    IERC4626 usdsVault = IERC4626(MORPHO_VAULT_USDS);
    IERC4626 usdcVault = IERC4626(MORPHO_VAULT_USDC);

    function setUp() public override {
        super.setUp();

        vm.startPrank(Base.SPARK_EXECUTOR);

        // Add in the idle markets so deposits can be made
        MarketParams memory usdsParams = MarketParams({
            loanToken:       Base.USDS,
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            0
        });
        MarketParams memory usdcParams = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            0
        });
        IMorpho(MORPHO).createMarket(
            usdsParams
        );
        // USDC idle market already exists
        IMetaMorpho(MORPHO_VAULT_USDS).submitCap(
            usdsParams,
            type(uint184).max
        );
        IMetaMorpho(MORPHO_VAULT_USDC).submitCap(
            usdcParams,
            type(uint184).max
        );

        skip(1 days);

        IMetaMorpho(MORPHO_VAULT_USDS).acceptCap(usdsParams);
        IMetaMorpho(MORPHO_VAULT_USDC).acceptCap(usdcParams);

        Id[] memory supplyQueueUSDS = new Id[](1);
        supplyQueueUSDS[0] = MarketParamsLib.id(usdsParams);
        IMetaMorpho(MORPHO_VAULT_USDS).setSupplyQueue(supplyQueueUSDS);

        Id[] memory supplyQueueUSDC = new Id[](1);
        supplyQueueUSDC[0] = MarketParamsLib.id(usdcParams);
        IMetaMorpho(MORPHO_VAULT_USDC).setSupplyQueue(supplyQueueUSDC);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                MORPHO_VAULT_USDS
            ),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                MORPHO_VAULT_USDC
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_4626_WITHDRAW(),
                MORPHO_VAULT_USDS
            ),
            10_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_4626_WITHDRAW(),
                MORPHO_VAULT_USDC
            ),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        foreignController.setMaxExchangeRate(MORPHO_VAULT_USDS, usdsVault.convertToShares(1e18), 1e18);
        foreignController.setMaxExchangeRate(MORPHO_VAULT_USDC, usdcVault.convertToShares(1e18), 1e18);

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22841965;  // November 24, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used
// TODO: Refactor tests here to be generic 4626, testing morpho as a subset, rename file and functions

contract ForeignController_Morpho_Deposit_FailureTests is Morpho_TestBase {

    function test_morpho_deposit_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 0);
    }

    function test_morpho_deposit_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 0);
    }

    function test_morpho_deposit_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.depositERC4626(makeAddr("fake-token"), 1e18, 0);
    }

    function test_morpho_usds_deposit_rateLimitedBoundary() external {
        deal(Base.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18 + 1, 0);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18, 0);
    }

    function test_morpho_usdc_deposit_rateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 25_000_000e6 + 1, 0);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 25_000_000e6, 0);
    }

    function test_depositERC4626_exchangeRateBoundary() external {
        deal(Base.USDS, address(almProxy), 25_000_000e18);

        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignController.setMaxExchangeRate(MORPHO_VAULT_USDS, usdsVault.convertToShares(1e18), 1e18 - 1);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("FC/exchange-rate-too-high");
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18, 0);

        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignController.setMaxExchangeRate(MORPHO_VAULT_USDS, usdsVault.convertToShares(1e18), 1e18);
        vm.stopPrank();

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18, 0);
    }

    function test_morpho_usdc_deposit_zeroExchangeRate() external {
        deal(Base.USDS, address(almProxy), 25_000_000e18);

        vm.prank(Base.SPARK_EXECUTOR);
        foreignController.setMaxExchangeRate(MORPHO_VAULT_USDS, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("FC/exchange-rate-too-high");
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1e18, 0);
    }

    function test_morpho_deposit_minSharesOutNotMetBoundary() external {
        deal(Base.USDS, address(almProxy), 25_000_000e18);

        uint256 overBoundaryShares = usdsVault.convertToShares(25_000_000e18) + 1;
        uint256 atBoundaryShares   = usdsVault.convertToShares(25_000_000e18);

        vm.startPrank(relayer);
        vm.expectRevert("FC/min-shares-out-not-met");
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18, overBoundaryShares);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18, atBoundaryShares);
    }

}

contract ForeignController_Morpho_Deposit_SuccessTests is Morpho_TestBase {

    function test_morpho_usds_deposit() public {
        deal(Base.USDS, address(almProxy), 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))),          0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                             1_000_000e18);
        assertEq(IERC20(Base.USDS).allowance(address(almProxy), address(MORPHO_VAULT_USDS)), 0);

        vm.record();

        vm.prank(relayer);
        assertEq(
            foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18),
            1_000_000e18
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))),          1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                             0);
        assertEq(IERC20(Base.USDS).allowance(address(almProxy), address(MORPHO_VAULT_USDS)), 0);
    }

    function test_morpho_usdc_deposit() public {
        deal(Base.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))),          0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                             1_000_000e6);
        assertEq(IERC20(Base.USDC).allowance(address(almProxy), address(MORPHO_VAULT_USDC)), 0);

        vm.prank(relayer);
        assertEq(
            foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6, 1_000_000e6),
            1_000_000e18
        );

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))),          1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                             0);
        assertEq(IERC20(Base.USDC).allowance(address(almProxy), address(MORPHO_VAULT_USDC)), 0);
    }

}

contract ForeignController_Morpho_Withdraw_FailureTests is Morpho_TestBase {

    function test_morpho_withdraw_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);
    }

    function test_morpho_withdraw_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);
    }

    function test_morpho_withdraw_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.withdrawERC4626(makeAddr("fake-token"), 1_000_000e18, 1_000_000e18);
    }

    function test_morpho_usds_withdraw_rateLimitBoundary() external {
        deal(Base.USDS, address(almProxy), 10_000_000e18 + 1);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 10_000_000e18 + 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 10_000_000e18 + 1, 10_000_000e18 + 1);

        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 10_000_000e18, 10_000_000e18);

        vm.stopPrank();
    }

    function test_morpho_usdc_withdraw_rateLimitBoundary() external {
        deal(Base.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDC, 10_000_000e6 + 1, 0);

        uint256 shares = usdcVault.convertToShares(10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawERC4626(
            MORPHO_VAULT_USDC,
            10_000_000e6 + 1,
            shares
        );

        foreignController.withdrawERC4626(MORPHO_VAULT_USDC, 10_000_000e6, 10_000_000e18);

        vm.stopPrank();
    }

    function test_morpho_withdraw_maxSharesInNotMetBoundary() external {
        deal(Base.USDS, address(almProxy), 10_000_000e18);

        uint256 underBoundaryShares = usdsVault.previewWithdraw(10_000_000e18) - 1;
        uint256 atBoundaryShares    = usdsVault.previewWithdraw(10_000_000e18);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 10_000_000e18, 0);

        vm.expectRevert("FC/shares-burned-too-high");
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 10_000_000e18, underBoundaryShares);

        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 10_000_000e18, atBoundaryShares);

        vm.stopPrank();
    }


}

contract ForeignController_Morpho_Withdraw_SuccessTests is Morpho_TestBase {

    function test_morpho_usds_withdraw() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_DEPOSIT(),
            MORPHO_VAULT_USDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_WITHDRAW(),
            MORPHO_VAULT_USDS
        );

        deal(Base.USDS, address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        vm.record();

        vm.prank(relayer);
        assertEq(
            foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18),
            1_000_000e18
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    1_000_000e18);
    }

    function test_morpho_usdc_withdraw() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_DEPOSIT(),
            MORPHO_VAULT_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_WITHDRAW(),
            MORPHO_VAULT_USDC
        );

        deal(Base.USDC, address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6, 1_000_000e18);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        vm.record();

        vm.prank(relayer);
        assertEq(
            foreignController.withdrawERC4626(MORPHO_VAULT_USDC, 1_000_000e6, 1_000_000e18),
            1_000_000e18
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    1_000_000e6);
    }

}

contract ForeignController_Morpho_Redeem_FailureTests is Morpho_TestBase {

    function test_morpho_redeem_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);
    }

    function test_morpho_redeem_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);
    }

    function test_morpho_redeem_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_4626_WITHDRAW(),
                MORPHO_VAULT_USDS
            ),
            0,
            0
        );
        vm.stopPrank();

        deal(Base.USDS, address(almProxy), 1_000_000e18);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);

        vm.stopPrank();
    }

    function test_morpho_usds_redeem_rateLimitBoundary() external {
        deal(Base.USDS, address(almProxy), 20_000_000e18);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 20_000_000e18, 0);

        uint256 overBoundaryShares = usdsVault.convertToShares(10_000_000e18 + 1);
        uint256 atBoundaryShares   = usdsVault.convertToShares(10_000_000e18);

        assertEq(usdsVault.previewRedeem(overBoundaryShares), 10_000_000e18 + 1);
        assertEq(usdsVault.previewRedeem(atBoundaryShares),   10_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, overBoundaryShares, 10_000_000e18 + 1);

        foreignController.redeemERC4626(MORPHO_VAULT_USDS, atBoundaryShares, 10_000_000e18);

        vm.stopPrank();
    }

    function test_morpho_usdc_redeem_rateLimitBoundary() external {
        deal(Base.USDC, address(almProxy), 20_000_000e18);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDC, 20_000_000e6, 0);

        uint256 overBoundaryShares = usdcVault.convertToShares(10_000_000e6 + 1);
        uint256 atBoundaryShares   = usdcVault.convertToShares(10_000_000e6);

        assertEq(usdcVault.previewRedeem(overBoundaryShares), 10_000_000e6 + 1);
        assertEq(usdcVault.previewRedeem(atBoundaryShares),   10_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.redeemERC4626(MORPHO_VAULT_USDC, overBoundaryShares, 0);

        foreignController.redeemERC4626(MORPHO_VAULT_USDC, atBoundaryShares, 0);

        vm.stopPrank();
    }

    function test_morpho_redeem_minAssetsOutNotMetBoundary() external {
        deal(Base.USDS, address(almProxy), 10_000_000e18);

        uint256 overBoundaryAssets = usdsVault.convertToAssets(10_000_000e18) + 1;
        uint256 atBoundaryAssets   = usdsVault.convertToAssets(10_000_000e18);

        vm.startPrank(relayer);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 10_000_000e18, 10_000_000e18);

        vm.expectRevert("FC/min-assets-out-not-met");
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 10_000_000e18, overBoundaryAssets);

        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 10_000_000e18, atBoundaryAssets);

        vm.stopPrank();
    }

}

contract ForeignController_Morpho_Redeem_SuccessTests is Morpho_TestBase {

    function test_morpho_usds_redeem() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_DEPOSIT(),
            MORPHO_VAULT_USDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_WITHDRAW(),
            MORPHO_VAULT_USDS
        );

        deal(Base.USDS, address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18, 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        uint256 shares = usdsVault.balanceOf(address(almProxy));

        vm.record();

        vm.prank(relayer);
        assertEq(
            foreignController.redeemERC4626(MORPHO_VAULT_USDS, shares, 1_000_000e18),
            1_000_000e18
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    1_000_000e18);
    }

    function test_morpho_usdc_redeem() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_DEPOSIT(),
            MORPHO_VAULT_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_4626_WITHDRAW(),
            MORPHO_VAULT_USDC
        );

        deal(Base.USDC, address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6, 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        uint256 shares = usdcVault.balanceOf(address(almProxy));

        vm.record();

        vm.prank(relayer);
        assertEq(
            foreignController.redeemERC4626(MORPHO_VAULT_USDC, shares, 1_000_000e6),
            1_000_000e6
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    1_000_000e6);
    }

}
