// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IFarmFacet } from "../../src/facets/farm/IFarmFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

abstract contract Farm_TestBase is ForkTestBase {

    address internal constant FARM = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;  // USDS SPK farm

    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            mainnetController.farm_getDepositRateLimitKey(FARM, Ethereum.USDS),
            10_000_000e18,
            uint256(1_000_000e18) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.farm_getWithdrawRateLimitKey(FARM),
            10_000_000e18,
            uint256(1_000_000e6) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.farm_getClaimRewardRateLimitKey(FARM),
            type(uint256).max,
            0
        );

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22982805;  // July 23, 2025
    }

}

contract MainnetController_Farm_Deposit_Tests is Farm_TestBase {

    function test_depositToFarm_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.farm_deposit(FARM, 1_000_000e18);
    }

    function test_depositToFarm_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.farm_deposit(FARM, 1_000_000e18);
    }

    function test_depositToFarm_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.farm_getDepositRateLimitKey(FARM, Ethereum.USDS),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 0);
    }

    function test_depositToFarm_rateLimitsBoundary() external {
        bytes32 key = mainnetController.farm_getDepositRateLimitKey(FARM, Ethereum.USDS);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18 + 1);

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18);
    }

    function test_depositToFarm() external {
        bytes32 depositKey = mainnetController.farm_getDepositRateLimitKey(FARM, Ethereum.USDS);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                            1_000_000e18);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),                0);
        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), FARM), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmDeposit(FARM, 1_000_000e18);

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 9_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                            0);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),                1_000_000e18);
        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), FARM), 0);
    }

}

contract MainnetController_Farm_ClaimReward_Tests is Farm_TestBase {

    function test_claimRewardFromFarm_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.farm_claimReward(FARM);
    }

    function test_claimRewardFromFarm_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.farm_claimReward(FARM);
    }

    function test_claimRewardFromFarm_invalidAction() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.farm_getClaimRewardRateLimitKey(FARM),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("FarmFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.farm_claimReward(FARM);
    }

    function test_claimRewardFromFarm() external {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                     1_000_000e18);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),         0);
        assertEq(IERC20Like(Ethereum.SPK).balanceOf(address(almProxy)), 0);

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                     0);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),         1_000_000e18);
        assertEq(IERC20Like(Ethereum.SPK).balanceOf(address(almProxy)), 0);

        skip(1 days);

        uint256 expectedReward = 2930.857045118398e18;

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmReward(FARM, expectedReward);

        vm.prank(allocator);
        assertEq(mainnetController.farm_claimReward(FARM), expectedReward);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IERC20Like(Ethereum.SPK).balanceOf(address(almProxy)), expectedReward);

        // Staked position is untouched.
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)), 1_000_000e18);

        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmReward(FARM, 0);

        vm.prank(allocator);
        assertEq(mainnetController.farm_claimReward(FARM), 0);
    }

}

contract MainnetController_Farm_Withdraw_Tests is Farm_TestBase {

    function test_withdrawFromFarm_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.farm_withdraw(FARM, 1_000_000e18);
    }

    function test_withdrawFromFarm_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.farm_withdraw(FARM, 1_000_000e18);
    }

    function test_withdrawFromFarm_zeroMaxAmount() external {
        bytes32 key = mainnetController.farm_getWithdrawRateLimitKey(FARM);

        deal(Ethereum.USDS, address(almProxy), 1);

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.farm_withdraw(FARM, 1);
    }

    function test_withdrawFromFarm_rateLimitsBoundary() external {
        bytes32 key = mainnetController.farm_getWithdrawRateLimitKey(FARM);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18 + 1);

        vm.startPrank(allocator);

        mainnetController.farm_deposit(FARM, 1_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.farm_withdraw(FARM, 1_000_000e18 + 1);

        mainnetController.farm_withdraw(FARM, 1_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawFromFarm() external {
        bytes32 withdrawKey = mainnetController.farm_getWithdrawRateLimitKey(FARM);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmDeposit({ farm: FARM, amount: 1_000_000e18 });

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                     0);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),         1_000_000e18);
        assertEq(IERC20Like(Ethereum.SPK).balanceOf(address(almProxy)), 0);

        skip(1 days);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmWithdraw(FARM, 1_000_000e18);

        vm.prank(allocator);
        mainnetController.farm_withdraw(FARM, 1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),                     1_000_000e18);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)),         0);
        assertEq(IERC20Like(Ethereum.SPK).balanceOf(address(almProxy)), 0); // No reward claimed
    }

    function test_withdrawFromFarm_partialFill() external {
        bytes32 withdrawKey = mainnetController.farm_getWithdrawRateLimitKey(FARM);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        vm.prank(allocator);
        mainnetController.farm_deposit(FARM, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey),   10_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),             0);
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)), 1_000_000e18);

        skip(1 days);

        // Simulate the farm returning fewer tokens than requested (slashing/fees/rounding): mock
        // withdraw to a no-op so no staking tokens are returned to the proxy.
        vm.mockCall(FARM, abi.encodeWithSignature("withdraw(uint256)", 1_000_000e18), "");

        vm.record();

        // The facet decrements the rate limit by the ACTUAL amount withdrawn (the balance delta,
        // here 0), not the requested amount.
        vm.expectEmit(address(mainnetController));
        emit IFarmFacet.FarmWithdraw(FARM, 0);

        vm.prank(allocator);
        mainnetController.farm_withdraw(FARM, 1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey),   10_000_000e18);  // Unchanged: decremented by 0
        assertEq(USDS.balanceOf(address(almProxy)),             0);              // No funds returned
        assertEq(IERC20Like(FARM).balanceOf(address(almProxy)), 1_000_000e18);   // Staked position untouched
    }

}
