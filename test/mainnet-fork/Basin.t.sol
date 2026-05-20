// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IBasinFacet } from "../../src/facets/basin/IBasinFacet.sol";

import { GroveBasin }        from "../../lib/grove-basin/src/GroveBasin.sol";
import { FixedRateProvider } from "../../lib/grove-basin/src/rate-providers/FixedRateProvider.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

abstract contract Basin_TestBase is ForkTestBase {

    GroveBasin internal groveBasin;

    uint256 internal constant SEED_AMOUNT = 1_000e18;

    function setUp() public virtual override {
        super.setUp();

        // Deploy fixed rate providers (1:1 USD pricing, never stale).
        FixedRateProvider rateProvider = new FixedRateProvider(1e27);

        // Deploy GroveBasin with almProxy as liquidityProvider.
        groveBasin = new GroveBasin(
            address(this),          // owner
            address(almProxy),      // liquidityProvider
            Ethereum.USDC,          // swapToken
            Ethereum.USDS,          // collateralToken (what we test with)
            Ethereum.DAI,           // creditToken
            address(rateProvider),
            address(rateProvider),
            address(rateProvider)
        );

        // Seed the basin with `depositInitial`.
        deal(Ethereum.USDS, address(this), SEED_AMOUNT);
        IERC20Like(Ethereum.USDS).approve(address(groveBasin), SEED_AMOUNT);
        groveBasin.depositInitial(Ethereum.USDS, SEED_AMOUNT);

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            mainnetController.basin_getDepositRateLimitKey(address(groveBasin), Ethereum.USDS),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        rateLimits.setRateLimitData(
            mainnetController.basin_getWithdrawRateLimitKey(address(groveBasin), Ethereum.USDS),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        vm.stopPrank();

        vm.label(address(groveBasin), "GroveBasin");
    }

}

contract MainnetController_Basin_Deposit_Tests is Basin_TestBase {

    function test_depositBasin_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.basin_deposit(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_depositBasin_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.basin_deposit(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_depositBasin_zeroMaxAmount() external {
        bytes32 key = mainnetController.basin_getDepositRateLimitKey(address(groveBasin), Ethereum.USDS);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.basin_deposit(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_depositBasin_rateLimitBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            5_000_000e18 + 1,
            5_000_000e18 + 1
        );

        vm.prank(allocator);
        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            5_000_000e18,
            5_000_000e18
        );
    }

    function test_depositBasin_minSharesOutNotMetBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 1e18);

        uint256 atBoundaryShares   = groveBasin.previewDeposit(Ethereum.USDS, 1e18);
        uint256 overBoundaryShares = atBoundaryShares + 1;

        vm.expectRevert("BasinFacet/min-shares-out-not-met");
        vm.prank(allocator);
        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            1e18,
            overBoundaryShares
        );

        vm.prank(allocator);
        mainnetController.basin_deposit(address(groveBasin), Ethereum.USDS, 1e18, atBoundaryShares);
    }

    function test_depositBasin() external {
        uint256 depositAmount = 1_000_000e18;

        deal(Ethereum.USDS, address(almProxy), depositAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),   depositAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(groveBasin)), SEED_AMOUNT);

        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), address(groveBasin)), 0);

        uint256 expectedShares = groveBasin.previewDeposit(Ethereum.USDS, depositAmount);

        assertEq(expectedShares, depositAmount);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinDeposit(address(groveBasin), Ethereum.USDS, depositAmount, expectedShares);

        vm.prank(allocator);
        uint256 shares = mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            depositAmount,
            expectedShares
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, expectedShares);
        assertGt(shares, 0);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),   0);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(groveBasin)), depositAmount + SEED_AMOUNT);

        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), address(groveBasin)), 0);
    }

    function test_depositBasin_rateLimited() external {
        bytes32 key = mainnetController.basin_getDepositRateLimitKey(address(groveBasin), Ethereum.USDS);

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        vm.startPrank(allocator);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            1_000_000e18,
            1_000_000e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);

        skip(1 hours);

        deal(Ethereum.USDS, address(almProxy), 4_249_999.999999999999998400e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.999999999999998400e18);

        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            4_249_999.999999999999998400e18,
            4_249_999.999999999999998400e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.basin_deposit(address(groveBasin), Ethereum.USDS, 1, 1);

        vm.stopPrank();
    }

}

contract MainnetController_Basin_Withdraw_Tests is Basin_TestBase {

    function setUp() public virtual override {
        super.setUp();

        bytes32 depositKey = mainnetController.basin_getDepositRateLimitKey(address(groveBasin), Ethereum.USDS);

        // Step 1: Set a higher rate limit for deposits to allow for withdrawals boundaries tests.
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);

        // Step 2: Deposit enough to cover the withdraw boundaries test.
        deal(Ethereum.USDS, address(almProxy), 10_000_000e18);
        vm.prank(allocator);
        mainnetController.basin_deposit(
            address(groveBasin),
            Ethereum.USDS,
            10_000_000e18,
            10_000_000e18
        );
    }

    function test_withdrawBasin_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.basin_withdraw(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_withdrawBasin_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.basin_withdraw(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_withdrawBasin_minConversionRateNotMetBoundary() external {
        vm.expectRevert("BasinFacet/min-conversion-rate-not-met");
        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            1e18,
            1e18 + 1
        );

        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            1e18,
            1e18
        );
    }

    function test_withdrawBasin_zeroMaxAmount() external {
        bytes32 withdrawKey = mainnetController.basin_getWithdrawRateLimitKey(address(groveBasin), Ethereum.USDS);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(withdrawKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.basin_withdraw(address(groveBasin), Ethereum.USDS, 1e18, 1e18);
    }

    function test_withdrawBasin_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            5_000_000e18 + 1,
            1e18
        );

        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            5_000_000e18,
            1e18
        );
    }

    function test_withdrawBasin() external {
        uint256 withdrawAmount = 1_000_000e18;

        uint256 proxyBalBefore = IERC20Like(Ethereum.USDS).balanceOf(address(almProxy));
        uint256 basinBalBefore = IERC20Like(Ethereum.USDS).balanceOf(address(groveBasin));

        assertEq(proxyBalBefore, 0);
        assertGe(basinBalBefore, withdrawAmount);

        vm.prank(address(almProxy));
        ( uint256 expectedShares, ) = groveBasin.previewWithdraw(Ethereum.USDS, withdrawAmount);

        assertEq(expectedShares, withdrawAmount);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinWithdraw(address(groveBasin), Ethereum.USDS, withdrawAmount, expectedShares);

        vm.prank(allocator);
        uint256 assetsWithdrawn = mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            withdrawAmount,
            1e18
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(assetsWithdrawn, withdrawAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),   withdrawAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(groveBasin)), basinBalBefore - withdrawAmount);
    }

    function test_withdrawBasin_rateLimited() external {
        bytes32 key = mainnetController.basin_getWithdrawRateLimitKey(address(groveBasin), Ethereum.USDS);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            1_000_000e18,
            1e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.999999999999998400e18);

        vm.prank(allocator);
        mainnetController.basin_withdraw(
            address(groveBasin),
            Ethereum.USDS,
            4_249_999.999999999999998400e18,
            1e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.basin_withdraw(address(groveBasin), Ethereum.USDS, 1, 1e18);
    }

}
