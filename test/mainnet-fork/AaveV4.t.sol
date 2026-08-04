// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum as GroveEthereum } from "../../lib/grove-address-registry/src/Ethereum.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IAaveV4Facet } from "../../src/facets/aave-v4/IAaveV4Facet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IAaveV4SpokeLike {
    function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256);
}

interface IAaveV4HubLike {
    function getAssetLiquidity(uint256 assetId)  external view returns (uint256);
    function getAddedAssets(uint256 assetId)     external view returns (uint256);
    function getAddedShares(uint256 assetId)     external view returns (uint256);
    function getAssetDeficitRay(uint256 assetId) external view returns (uint256);
}

abstract contract AaveV4_TestBase is ForkTestBase {

    // USDC is suppliable on both the Main and Forex spokes via the same Core Hub asset (assetId 5),
    // which lets the tests exercise per-(spoke, reserveId) rate limits across two spokes for one asset.
    address internal constant MAIN_SPOKE  = GroveEthereum.AAVE_V4_MAIN_SPOKE;
    address internal constant FOREX_SPOKE = GroveEthereum.AAVE_V4_FOREX_SPOKE;
    address internal constant CORE_HUB    = GroveEthereum.AAVE_V4_CORE_HUB;

    uint256 internal constant MAIN_USDC_RESERVE_ID  = 7;  // USDC (6 decimals),  Core Hub assetId 5
    uint256 internal constant MAIN_WETH_RESERVE_ID  = 0;  // WETH (18 decimals), Core Hub assetId 0
    uint256 internal constant FOREX_USDC_RESERVE_ID = 1;  // USDC (6 decimals),  Core Hub assetId 5

    uint16 internal constant USDC_ASSET_ID = 5;
    uint16 internal constant WETH_ASSET_ID = 0;

    // Controller-side deposit limits sit above Aave's on-chain supply caps, so they only bind in the
    // dedicated rate-limit boundary tests.
    uint256 internal constant USDC_DEPOSIT_LIMIT = 25_000_000e6;
    uint256 internal constant WETH_DEPOSIT_LIMIT = 20_000e18;

    uint256 internal constant USDC_WITHDRAW_LIMIT = 10_000_000e6;
    uint256 internal constant WETH_WITHDRAW_LIMIT = 10_000e18;

    uint256 internal constant USDC_DEPOSIT_AMOUNT = 1_000_000e6;
    uint256 internal constant WETH_DEPOSIT_AMOUNT = 100e18;

    IERC20 internal weth = IERC20(Ethereum.WETH);

    bytes32 internal mainUsdcDepositKey;
    bytes32 internal mainUsdcWithdrawKey;
    bytes32 internal mainWethDepositKey;
    bytes32 internal mainWethWithdrawKey;
    bytes32 internal forexUsdcDepositKey;
    bytes32 internal forexUsdcWithdrawKey;

    uint256 internal startingHubBalanceUsdc;
    uint256 internal startingHubBalanceWeth;

    function setUp() public virtual override {
        super.setUp();

        mainUsdcDepositKey   = mainnetController.aaveV4_getDepositRateLimitKey(MAIN_SPOKE,   MAIN_USDC_RESERVE_ID,  CORE_HUB, USDC_ASSET_ID, address(usdc));
        mainUsdcWithdrawKey  = mainnetController.aaveV4_getWithdrawRateLimitKey(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID);
        mainWethDepositKey   = mainnetController.aaveV4_getDepositRateLimitKey(MAIN_SPOKE,   MAIN_WETH_RESERVE_ID,  CORE_HUB, WETH_ASSET_ID, address(weth));
        mainWethWithdrawKey  = mainnetController.aaveV4_getWithdrawRateLimitKey(MAIN_SPOKE,  MAIN_WETH_RESERVE_ID);
        forexUsdcDepositKey  = mainnetController.aaveV4_getDepositRateLimitKey(FOREX_SPOKE,  FOREX_USDC_RESERVE_ID, CORE_HUB, USDC_ASSET_ID, address(usdc));
        forexUsdcWithdrawKey = mainnetController.aaveV4_getWithdrawRateLimitKey(FOREX_SPOKE, FOREX_USDC_RESERVE_ID);

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(mainUsdcDepositKey,  USDC_DEPOSIT_LIMIT, USDC_DEPOSIT_LIMIT / 1 days);
        rateLimits.setRateLimitData(mainWethDepositKey,  WETH_DEPOSIT_LIMIT, WETH_DEPOSIT_LIMIT / 1 days);
        rateLimits.setRateLimitData(forexUsdcDepositKey, USDC_DEPOSIT_LIMIT, USDC_DEPOSIT_LIMIT / 1 days);

        rateLimits.setRateLimitData(mainUsdcWithdrawKey,  USDC_WITHDRAW_LIMIT, USDC_WITHDRAW_LIMIT / 1 days);
        rateLimits.setRateLimitData(mainWethWithdrawKey,  WETH_WITHDRAW_LIMIT, WETH_WITHDRAW_LIMIT / 1 days);
        rateLimits.setRateLimitData(forexUsdcWithdrawKey, USDC_WITHDRAW_LIMIT, USDC_WITHDRAW_LIMIT / 1 days);

        // Per-(spoke, reserveId) slippage: each market gets its own rounding tolerance.
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID,  1e18 - 1e4);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE,  MAIN_WETH_RESERVE_ID,  1e18 - 1e4);
        mainnetController.aaveV4_setMaxSlippage(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, 1e18 - 1e4);

        vm.stopPrank();

        startingHubBalanceUsdc = usdc.balanceOf(CORE_HUB);
        startingHubBalanceWeth = weth.balanceOf(CORE_HUB);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 25574000;  // July 2026 (Aave v4 live on mainnet since March 2026)
    }

    function _suppliedAssets(address spoke, uint256 reserveId) internal view returns (uint256) {
        return IAaveV4SpokeLike(spoke).getUserSuppliedAssets(reserveId, address(almProxy));
    }

}

// NOTE: Only testing USDC on the Main Spoke for non-rate-limit failures as the revert path is asset-
//       and spoke-agnostic.

contract MainnetController_AaveV4_Deposit_Tests is AaveV4_TestBase {

    function test_depositAaveV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_zeroMaxSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 0);

        vm.expectRevert("AaveV4Facet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_assetDeficit() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        // Simulate an outstanding Hub deficit for USDC (assetId 5): any deficit blocks the deposit.
        vm.mockCall(
            CORE_HUB,
            abi.encodeWithSelector(IAaveV4HubLike.getAssetDeficitRay.selector, USDC_ASSET_ID),
            abi.encode(uint256(1))
        );

        vm.expectRevert("AaveV4Facet/asset-deficit");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        // The guard is hardcoded to zero with no admin override, so the deposit only clears once the
        // deficit itself is gone.
        vm.clearMockedCalls();

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT - 1);
    }

    function test_depositAaveV4_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_usdc_rateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_LIMIT + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_LIMIT + 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_weth_rateLimitedBoundary() external {
        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_LIMIT + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_LIMIT + 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);
    }

    // The reserve credits a round-down share amount, so a 1e18 tolerance always trips the guard and
    // one wei below it is the strictest tolerance that still admits an honest deposit.
    function test_depositAaveV4_usdc_slippageTooHighBoundary() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1e18);

        vm.expectRevert("AaveV4Facet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1e18 - 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    // Pins why an exact 1:1 (1e18) tolerance is unusable: the reserve credits a round-down share
    // amount, so a 1e18 tolerance reverts every deposit, accrual or not, while one wei below it
    // still clears an honest deposit.
    function test_depositAaveV4_usdc_slippageOneToOneAfterAccrualBoundary() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        skip(365 days);

        // Interest accrued: the supplied position now exceeds the original deposit (share price > 1:1).
        assertGt(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1e18);

        vm.expectRevert("AaveV4Facet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        // Accrual can never wedge deposits: the strictest usable tolerance still admits one.
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aaveV4_setMaxSlippage(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 1e18 - 1);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_usdc() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        assertEq(usdc.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),  0);
        assertEq(usdc.balanceOf(address(almProxy)),                  USDC_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(CORE_HUB),                           startingHubBalanceUsdc);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),  USDC_DEPOSIT_AMOUNT - 1);
        assertEq(usdc.balanceOf(address(almProxy)),                  0);
        assertEq(usdc.balanceOf(CORE_HUB),                           startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT);
    }

    function test_depositAaveV4_weth() external {
        // WETH share price is above 1:1 (accrued interest).
        assertGt(IAaveV4HubLike(CORE_HUB).getAddedAssets(WETH_ASSET_ID), IAaveV4HubLike(CORE_HUB).getAddedShares(WETH_ASSET_ID));

        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        assertEq(weth.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID),  0);
        assertEq(weth.balanceOf(address(almProxy)),                  WETH_DEPOSIT_AMOUNT);
        assertEq(weth.balanceOf(CORE_HUB),                           startingHubBalanceWeth);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey), WETH_DEPOSIT_LIMIT);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weth.allowance(address(almProxy), MAIN_SPOKE),      0);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID),  WETH_DEPOSIT_AMOUNT - 1);
        assertEq(weth.balanceOf(address(almProxy)),                  0);
        assertEq(weth.balanceOf(CORE_HUB),                           startingHubBalanceWeth + WETH_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey), WETH_DEPOSIT_LIMIT - WETH_DEPOSIT_AMOUNT);
    }

}

// NOTE: Only testing USDC for non-rate-limit failures as the revert path is asset-agnostic.

contract MainnetController_AaveV4_Withdraw_Tests is AaveV4_TestBase {

    function test_withdrawAaveV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_withdrawAaveV4_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
    }

    function test_withdrawAaveV4_zeroMaxAmount() external {
        // Longer setup because the rate limit revert is at the end of the function.
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcWithdrawKey, 0, 0);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_withdrawAaveV4_usdc_rateLimitedBoundary() external {
        uint256 withdrawLimit = 500_000e6;

        // Necessary to be able to hit the withdrawal rate limit after a 1m deposit.
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcWithdrawKey, withdrawLimit, withdrawLimit / 1 days);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, withdrawLimit + 1);

        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, withdrawLimit);
        vm.stopPrank();
    }

    function test_withdrawAaveV4_weth_rateLimitedBoundary() external {
        uint256 withdrawLimit = 50e18;

        // Necessary to be able to hit the withdrawal rate limit after a 100 WETH deposit.
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainWethWithdrawKey, withdrawLimit, withdrawLimit / 1 days);

        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        vm.startPrank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, withdrawLimit + 1);

        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, withdrawLimit);
        vm.stopPrank();
    }

    function test_withdrawAaveV4_usdc() external {
        // Gentler slope than the default so the 1 hour deposit-limit refill is partial and observable.
        uint256 depositSlope = uint256(5_000_000e6) / 1 days;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, USDC_DEPOSIT_LIMIT, depositSlope);

        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        skip(1 hours);

        // The supplied position accrued interest, so it now exceeds the deposit.
        uint256 suppliedValue = _suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID);
        assertGt(suppliedValue, USDC_DEPOSIT_AMOUNT);

        assertEq(usdc.balanceOf(address(almProxy)),                   0);
        assertEq(usdc.balanceOf(CORE_HUB),                            startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT + depositSlope * 1 hours);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), USDC_WITHDRAW_LIMIT);

        uint256 partialAmount = 400_000e6;

        vm.record();

        // Partial withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, partialAmount);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, partialAmount), partialAmount);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.balanceOf(address(almProxy)),                   partialAmount);
        assertEq(usdc.balanceOf(CORE_HUB),                            startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT - partialAmount);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),   suppliedValue - partialAmount);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - USDC_DEPOSIT_AMOUNT + depositSlope * 1 hours + partialAmount);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), USDC_WITHDRAW_LIMIT - partialAmount);

        // Withdraw all, including the accrued interest
        uint256 remaining = _suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID);

        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, remaining);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, type(uint256).max), remaining);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), 0);
        assertEq(usdc.balanceOf(address(almProxy)),                 suppliedValue);

        // Deposit capacity restored up to the cap; withdraw capacity consumed by the full position.
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey), USDC_WITHDRAW_LIMIT - suppliedValue);

        // Interest was paid out of the Hub's other liquidity, reducing its cash below the start.
        assertEq(usdc.balanceOf(CORE_HUB), startingHubBalanceUsdc + USDC_DEPOSIT_AMOUNT - suppliedValue);
    }

    function test_withdrawAaveV4_weth() external {
        deal(Ethereum.WETH, address(almProxy), WETH_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, WETH_DEPOSIT_AMOUNT);

        skip(1 hours);

        // The supplied position accrued interest, so it now exceeds the deposit.
        uint256 suppliedValue = _suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID);
        assertGt(suppliedValue, WETH_DEPOSIT_AMOUNT);

        assertEq(weth.balanceOf(address(almProxy)),                   0);
        assertEq(weth.balanceOf(CORE_HUB),                            startingHubBalanceWeth + WETH_DEPOSIT_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  WETH_DEPOSIT_LIMIT);  // Refill capped at max
        assertEq(rateLimits.getCurrentRateLimit(mainWethWithdrawKey), WETH_WITHDRAW_LIMIT);

        // Withdraw all, including the accrued interest
        vm.expectEmit(address(mainnetController));
        emit IAaveV4Facet.AaveV4Withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, suppliedValue);

        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_WETH_RESERVE_ID, type(uint256).max), suppliedValue);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_WETH_RESERVE_ID), 0);
        assertEq(weth.balanceOf(address(almProxy)),                 suppliedValue);

        assertEq(rateLimits.getCurrentRateLimit(mainWethDepositKey),  WETH_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(mainWethWithdrawKey), WETH_WITHDRAW_LIMIT - suppliedValue);

        // Interest was paid out of the Hub's other liquidity, reducing its cash below the start.
        assertEq(weth.balanceOf(CORE_HUB), startingHubBalanceWeth + WETH_DEPOSIT_AMOUNT - suppliedValue);
    }

    function test_withdrawAaveV4_usdc_zeroDepositRateLimit() external {
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        // Zero deposit rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainUsdcDepositKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), 0);

        // Partial withdraw; the deposit restore is skipped
        vm.prank(allocator);
        assertEq(mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, 400_000e6), 400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey), 0);  // Stays at 0
    }

}

contract MainnetController_AaveV4_DonationInflationAttack_Test is AaveV4_TestBase {

    // Aave v3 lets an attacker inflate the share price by donating underlying to the aToken, whose
    // accounting derives from balanceOf. Aave v4's Hub tracks liquidity internally, so a raw donation
    // is inert and an honest deposit still receives fair value.
    function test_depositAaveV4_donationDoesNotInflateSharePrice() external {
        IAaveV4HubLike hub = IAaveV4HubLike(CORE_HUB);

        uint256 liquidityBefore = hub.getAssetLiquidity(USDC_ASSET_ID);
        uint256 assetsBefore    = hub.getAddedAssets(USDC_ASSET_ID);
        uint256 sharesBefore    = hub.getAddedShares(USDC_ASSET_ID);

        // Donate underlying straight to the Hub (the v3 inflation vector).
        uint256 donation = 1_000_000e6;
        deal(Ethereum.USDC, address(this), donation);
        usdc.transfer(CORE_HUB, donation);

        // Raw balance grew, but the Hub's internal accounting is untouched.
        assertEq(usdc.balanceOf(CORE_HUB),             startingHubBalanceUsdc + donation);
        assertEq(hub.getAssetLiquidity(USDC_ASSET_ID), liquidityBefore);
        assertEq(hub.getAddedAssets(USDC_ASSET_ID),    assetsBefore);
        assertEq(hub.getAddedShares(USDC_ASSET_ID),    sharesBefore);

        // Honest deposit still receives fair value (~1:1 net of rounding).
        deal(Ethereum.USDC, address(almProxy), USDC_DEPOSIT_AMOUNT);

        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, USDC_DEPOSIT_AMOUNT);

        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID), USDC_DEPOSIT_AMOUNT - 1);

        // Shares were minted against the deposit, proving the donation did not move the share price.
        assertGt(hub.getAddedShares(USDC_ASSET_ID), sharesBefore);
    }

}

contract MainnetController_AaveV4_TwoSpoke_Tests is AaveV4_TestBase {

    // The same underlying (USDC) supplied through two spokes (Main and Forex, both mapping to Core Hub
    // assetId 5) must have fully independent controller rate limits, since limits are keyed per
    // (spoke, reserveId). Amounts are kept small to stay within each spoke's own Aave add cap.
    function test_aaveV4_twoSpokeRateLimitIsolation() external {
        uint256 mainAmount  = 200_000e6;
        uint256 forexAmount = 100_000e6;

        deal(Ethereum.USDC, address(almProxy), mainAmount + forexAmount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),   USDC_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey),  USDC_DEPOSIT_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey),  USDC_WITHDRAW_LIMIT);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcWithdrawKey), USDC_WITHDRAW_LIMIT);

        // Main Spoke deposit consumes only Main Spoke capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, mainAmount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - mainAmount);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT);

        // Forex Spoke deposit consumes only Forex Spoke capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_deposit(FOREX_SPOKE, FOREX_USDC_RESERVE_ID, forexAmount);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),  USDC_DEPOSIT_LIMIT - mainAmount);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey), USDC_DEPOSIT_LIMIT - forexAmount);

        // Positions are tracked separately per spoke.
        assertEq(_suppliedAssets(MAIN_SPOKE,  MAIN_USDC_RESERVE_ID),  mainAmount  - 1);
        assertEq(_suppliedAssets(FOREX_SPOKE, FOREX_USDC_RESERVE_ID), forexAmount - 1);

        // Withdrawing from the Main Spoke restores only Main Spoke deposit capacity and consumes only
        // Main Spoke withdraw capacity.
        vm.prank(allocator);
        mainnetController.aaveV4_withdraw(MAIN_SPOKE, MAIN_USDC_RESERVE_ID, type(uint256).max);

        assertEq(rateLimits.getCurrentRateLimit(mainUsdcDepositKey),   USDC_DEPOSIT_LIMIT - 1);
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcDepositKey),  USDC_DEPOSIT_LIMIT - forexAmount);
        assertEq(rateLimits.getCurrentRateLimit(mainUsdcWithdrawKey),  USDC_WITHDRAW_LIMIT - (mainAmount - 1));
        assertEq(rateLimits.getCurrentRateLimit(forexUsdcWithdrawKey), USDC_WITHDRAW_LIMIT);
        assertEq(_suppliedAssets(MAIN_SPOKE, MAIN_USDC_RESERVE_ID),    0);
    }

}
