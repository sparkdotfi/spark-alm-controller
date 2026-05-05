// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { IPSM3Facet } from "../../src/facets/psm3/IPSM3Facet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

abstract contract PSM3_TestBase is ForkTestBase {

    function _assertState(
        address token,
        uint256 proxyBalance,
        uint256 psmBalance,
        uint256 proxyShares,
        uint256 totalShares,
        uint256 totalAssets,
        bytes32 rateLimitKey,
        uint256 currentRateLimit
    )
        internal
        view
    {
        address custodian = token == Base.USDC ? pocket : address(psmBase);

        assertEq(IERC20Like(token).balanceOf(address(almProxy)),          proxyBalance);
        assertEq(IERC20Like(token).balanceOf(address(foreignController)), 0);  // Should always be zero
        assertEq(IERC20Like(token).balanceOf(custodian),                  psmBalance);

        assertEq(psmBase.shares(address(almProxy)), proxyShares);
        assertEq(psmBase.totalShares(),             totalShares);
        assertEq(psmBase.totalAssets(),             totalAssets);

        assertEq(rateLimits.getCurrentRateLimit(rateLimitKey), currentRateLimit);

        // Should always be 0 before and after calls
        assertEq(usdsBase.allowance(address(almProxy), address(psmBase)), 0);
    }

}

contract ForeignController_PSM3_Deposit_Tests is PSM3_TestBase {

    function test_depositPSM_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.depositPSM(address(usdsBase), 1_000_000e18);
    }

    function test_depositPSM_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.depositPSM(address(usdsBase), 1_000_000e18);
    }

    function test_depositPSM_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.depositPSM(makeAddr("fake-token"), 1_000_000e18);
    }

    function test_depositPSM_usdcRateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 5_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.depositPSM(Base.USDC, 5_000_000e6 + 1);

        vm.prank(allocator);
        foreignController.depositPSM(Base.USDC, 5_000_000e6);
    }

    function test_depositPSM_usdsRateLimitedBoundary() external {
        deal(address(usdsBase), address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.depositPSM(address(usdsBase), 5_000_000e18 + 1);

        vm.prank(allocator);
        foreignController.depositPSM(address(usdsBase), 5_000_000e18);
    }

    function test_depositPSM_susdsRateLimitedBoundary() external {
        deal(address(susdsBase), address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.depositPSM(address(susdsBase), 5_000_000e18 + 1);

        vm.prank(allocator);
        foreignController.depositPSM(address(susdsBase), 5_000_000e18);
    }

    function test_depositPSM_depositUSDS() external {
        bytes32 key = foreignController.getPSMDepositRateLimitKey(address(usdsBase));

        deal(address(usdsBase), address(almProxy), 100e18);

        _assertState({
            token            : address(usdsBase),
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit(address(usdsBase), 100e18, 100e18);

        vm.prank(allocator);
        uint256 shares = foreignController.depositPSM(address(usdsBase), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100e18);

        _assertState({
            token            : address(usdsBase),
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

    function test_depositPSM_depositUSDC() external {
        bytes32 key = foreignController.getPSMDepositRateLimitKey(Base.USDC);

        deal(Base.USDC, address(almProxy), 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit(Base.USDC, 100e6, 100e18);

        vm.prank(allocator);
        uint256 shares = foreignController.depositPSM(Base.USDC, 100e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100e18);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_depositPSM_depositSUSDS() external {
        bytes32 key = foreignController.getPSMDepositRateLimitKey(address(susdsBase));

        deal(address(susdsBase), address(almProxy), 100e18);

        _assertState({
            token            : address(susdsBase),
            proxyBalance     : 100e18,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit(address(susdsBase), 100e18, 100.343092065533568746e18);

        vm.prank(allocator);
        uint256 shares = foreignController.depositPSM(address(susdsBase), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : address(susdsBase),
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

}

contract ForeignController_PSM3_Withdraw_Tests is PSM3_TestBase {

    function test_withdrawPSM_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.withdrawPSM(address(usdsBase), 100e18);
    }

    function test_withdrawPSM_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.withdrawPSM(address(usdsBase), 100e18);
    }

    function test_withdrawPSM_usdcZeroMaxAmount() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(Base.USDC);

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.withdrawPSM(Base.USDC, 100e18);
    }

    function test_withdrawPSM_usdsZeroMaxAmount() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(address(usdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.withdrawPSM(address(usdsBase), 100e18);
    }

    function test_withdrawPSM_susdsZeroMaxAmount() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(address(susdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.withdrawPSM(address(susdsBase), 100e18);
    }

    function test_withdrawPSM_usdcRateLimitedBoundary() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(Base.USDC);

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Base.USDC, address(almProxy), 1_000_000e6 + 1);

        vm.startPrank(allocator);

        foreignController.depositPSM(Base.USDC, 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(Base.USDC, 1_000_000e6 + 1);

        foreignController.withdrawPSM(Base.USDC, 1_000_000e6);

        vm.stopPrank();
    }

    function test_withdrawPSM_usdsRateLimitedBoundary() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(address(usdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usdsBase), address(almProxy), 1_000_000e18 + 1);

        vm.startPrank(allocator);

        foreignController.depositPSM(address(usdsBase), 1_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(usdsBase), 1_000_000e18 + 1);

        foreignController.withdrawPSM(address(usdsBase), 1_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawPSM_susdsRateLimitedBoundary() external {
        bytes32 withdrawKey = foreignController.getPSMWithdrawRateLimitKey(address(susdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        // NOTE: Need an extra wei because of rounding on conversion
        deal(address(susdsBase), address(almProxy), 1_000_000e18 + 2);

        vm.startPrank(allocator);

        foreignController.depositPSM(address(susdsBase), 1_000_000e18 + 2);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(susdsBase), 1_000_000e18 + 1);

        uint256 withdrawn = foreignController.withdrawPSM(address(susdsBase), 1_000_000e18);

        assertEq(withdrawn, 1_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawPSM_withdrawUSDS() external {
        bytes32 key = foreignController.getPSMWithdrawRateLimitKey(address(usdsBase));

        deal(address(usdsBase), address(almProxy), 100e18);

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit({ asset: address(usdsBase), amount: 100e18, shares: 100e18 });

        vm.prank(allocator);
        foreignController.depositPSM(address(usdsBase), 100e18);

        _assertState({
            token            : address(usdsBase),
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Withdraw(address(usdsBase), 100e18, 100e18);

        vm.prank(allocator);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(usdsBase), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e18);

        _assertState({
            token            : address(usdsBase),
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

    function test_withdrawPSM_withdrawUSDC() external {
        bytes32 key = foreignController.getPSMWithdrawRateLimitKey(Base.USDC);

        deal(Base.USDC, address(almProxy), 100e6);

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit({ asset: Base.USDC, amount: 100e6, shares: 100e18 });

        vm.prank(allocator);
        foreignController.depositPSM(Base.USDC, 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Withdraw(Base.USDC, 100e6, 100e18);

        vm.prank(allocator);
        uint256 amountWithdrawn = foreignController.withdrawPSM(Base.USDC, 100e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e6);

        _assertState({
            token            : Base.USDC,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_withdrawPSM_withdrawSUSDS() external {
        bytes32 key = foreignController.getPSMWithdrawRateLimitKey(address(susdsBase));

        deal(address(susdsBase), address(almProxy), 100e18);

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Deposit({
            asset  : address(susdsBase),
            amount : 100e18,
            shares : 100.343092065533568746e18
        });

        vm.prank(allocator);
        uint256 shares = foreignController.depositPSM(address(susdsBase), 100e18);

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : address(susdsBase),
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.record();

        vm.expectEmit(address(foreignController));
        emit IPSM3Facet.PSM3Withdraw(address(susdsBase), 100e18 - 1, shares);

        vm.prank(allocator);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(susdsBase), 100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountWithdrawn, 100e18 - 1);  // Rounding

        _assertState({
            token            : address(susdsBase),
            proxyBalance     : 100e18 - 1,  // Rounding
            psmBalance       : 1,           // Rounding
            proxyShares      : 0,
            totalShares      : 1e18,      // From seeding USDS
            totalAssets      : 1e18 + 1,  // From seeding USDS, rounding
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

}
