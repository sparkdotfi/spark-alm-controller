// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IWSTETHFacet } from "../../src/facets/wsteth/IWSTETHFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

interface IWithdrawalQueue {

    struct RequestStatus {
        uint256 amountOfSTETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool    isFinalized;
        bool    isClaimed;
    }

    function getLastRequestId() external view returns (uint256);

    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (RequestStatus[] memory statuses);

    function finalize(uint256 lastRequestIdToBeFinalized, uint256 maxShareRate) external payable;

}

interface IWSTETH is IERC20Like {

    function getStETHByWstETH(uint256 wstethAmount) external view returns (uint256);

}

abstract contract WSTETH_TestBase is ForkTestBase {

    IERC20Like       internal constant WETH           = IERC20Like(Ethereum.WETH);
    IWithdrawalQueue internal constant WITHDRAW_QUEUE = IWithdrawalQueue(Ethereum.WSTETH_WITHDRAW_QUEUE);
    IWSTETH          internal constant WSTETH         = IWSTETH(Ethereum.WSTETH);

    function _getBlock() internal pure override returns (uint256) {
        return 23469772; // September 29, 2025
    }

}

contract MainnetController_WSTETH_Deposit_Tests is WSTETH_TestBase {

    function test_depositToWSTETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wsteth_deposit(1e18);
    }

    function test_depositToWSTETH_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.wsteth_deposit(1e18);
    }

    function test_depositToWSTETH_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.wsteth_deposit(1e18);
    }

    function test_depositToWSTETH_rateLimitsBoundary() external {
        bytes32 key = mainnetController.wsteth_depositRateLimitKey();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.wsteth_deposit(1_000e18 + 1);

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHDeposit(1_000e18);

        vm.prank(allocator);
        mainnetController.wsteth_deposit(1_000e18);
    }

    function test_depositToWSTETH() external {
        bytes32 key = mainnetController.wsteth_depositRateLimitKey();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH,   address(almProxy), 2_000e18);
        deal(address(WSTETH), address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000e18);

        assertEq(WETH.balanceOf(address(almProxy)),   2_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHDeposit(1_000e18);

        vm.prank(allocator);
        mainnetController.wsteth_deposit(1_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(WETH.balanceOf(address(almProxy)),   1_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18 + 823.029395390731625220e18);

        assertEq(WSTETH.getStETHByWstETH(WSTETH.balanceOf(address(almProxy))), 2_215.023431241179326321e18);
    }

}

contract MainnetController_WSTETH_RequestWithdraw_Tests is WSTETH_TestBase {

    function test_requestWithdrawFromWSTETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wsteth_requestWithdraw(1e18);
    }

    function test_requestWithdrawFromWSTETH_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.wsteth_requestWithdraw(1e18);
    }

    function test_requestWithdrawFromWSTETH_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.wsteth_requestWithdraw(1e18);
    }

    function test_requestWithdrawFromWSTETH_rateLimitsBoundary() external {
        bytes32 requestWithdrawKey = mainnetController.wsteth_requestWithdrawRateLimitKey();

        uint256 stethLimit = WSTETH.getStETHByWstETH(500e18);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestWithdrawKey, stethLimit, stethLimit / 1 days);

        deal(Ethereum.WSTETH, address(almProxy), 500e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.wsteth_requestWithdraw(500e18 + 1);

        vm.prank(allocator);
        mainnetController.wsteth_requestWithdraw(500e18);
    }

    function test_requestWithdrawFromWSTETH() external {
        bytes32 depositKey         = mainnetController.wsteth_depositRateLimitKey();
        bytes32 requestWithdrawKey = mainnetController.wsteth_requestWithdrawRateLimitKey();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH,   address(almProxy), 2_000e18);
        deal(address(WSTETH), address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(WETH.balanceOf(address(almProxy)),   2_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18);

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHDeposit(1_000e18);

        vm.prank(allocator);
        mainnetController.wsteth_deposit(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(WETH.balanceOf(address(almProxy)),                                   1_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)),                                 1_000e18 + 823.029395390731625220e18);
        assertEq(WSTETH.allowance(address(almProxy), Ethereum.WSTETH_WITHDRAW_QUEUE), 0);

        assertEq(WSTETH.getStETHByWstETH(WSTETH.balanceOf(address(almProxy))), 2_215.023431241179326321e18);

        uint256 expectedStETHWithdrawal = WSTETH.getStETHByWstETH(500e18);

        assertEq(expectedStETHWithdrawal, 607.511715620589663161e18);

        vm.record();

        uint256[] memory expectedRequestIds = new uint256[](1);

        expectedRequestIds[0] = WITHDRAW_QUEUE.getLastRequestId() + 1;

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHRequestWithdraw(500e18, expectedStETHWithdrawal, expectedRequestIds);

        vm.prank(allocator);
        uint256[] memory requestIds = mainnetController.wsteth_requestWithdraw(500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(WSTETH.balanceOf(address(almProxy)),                                 1_000e18 + 323.029395390731625220e18);
        assertEq(WSTETH.allowance(address(almProxy), Ethereum.WSTETH_WITHDRAW_QUEUE), 0);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedStETHWithdrawal
        );

        assertEq(requestIds.length, 1);

        IWithdrawalQueue.RequestStatus[] memory statuses = WITHDRAW_QUEUE.getWithdrawalStatus(requestIds);

        assertApproxEqAbs(statuses[0].amountOfShares, 500e18, 1);

        assertEq(statuses[0].amountOfSTETH, expectedStETHWithdrawal);
        assertEq(statuses[0].owner,         address(almProxy));
        assertEq(statuses[0].timestamp,     block.timestamp);
        assertEq(statuses[0].isFinalized,   false);
        assertEq(statuses[0].isClaimed,     false);
    }

}

contract MainnetController_WSTETH_ClaimWithdrawal_Tests is WSTETH_TestBase {

    address internal constant FINALIZER = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function test_claimWithdrawalFromWSTETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wsteth_claimWithdrawal(1);
    }

    function test_claimWithdrawalFromWSTETH_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.wsteth_claimWithdrawal(1);
    }

    function test_claimWithdrawalFromWSTETH_failsWhenRequestRateLimitDoesNotExist() external {
        vm.expectRevert("WSTETHFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.wsteth_claimWithdrawal(1);
    }

    function test_claimWithdrawalFromWSTETH() external {
        bytes32 depositKey         = mainnetController.wsteth_depositRateLimitKey();
        bytes32 requestWithdrawKey = mainnetController.wsteth_requestWithdrawRateLimitKey();
        bytes32 claimWithdrawKey   = mainnetController.wsteth_claimWithdrawRateLimitKey();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18,          uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18,          uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.WETH,   address(almProxy), 2_000e18);
        deal(address(WSTETH), address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(WETH.balanceOf(address(almProxy)),   2_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18);

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHDeposit(1_000e18);

        vm.prank(allocator);
        mainnetController.wsteth_deposit(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(WETH.balanceOf(address(almProxy)),   1_000e18);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18 + 823.029395390731625220e18);

        assertEq(WSTETH.getStETHByWstETH(WSTETH.balanceOf(address(almProxy))), 2_215.023431241179326321e18);

        uint256 expectedStETHWithdrawal = WSTETH.getStETHByWstETH(5e18);

        assertEq(expectedStETHWithdrawal, 6.075117156205896631e18);

        uint256[] memory expectedRequestIds = new uint256[](1);

        expectedRequestIds[0] = WITHDRAW_QUEUE.getLastRequestId() + 1;

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHRequestWithdraw(5e18, expectedStETHWithdrawal, expectedRequestIds);

        // NOTE: Requesting for a small withdrawal so that it can be finalized.
        vm.prank(allocator);
        uint256[] memory requestIds = mainnetController.wsteth_requestWithdraw(5e18);

        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18 + 818.02939539073162522e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedStETHWithdrawal
        );

        assertEq(requestIds.length, 1);

        IWithdrawalQueue.RequestStatus[] memory statuses = WITHDRAW_QUEUE.getWithdrawalStatus(requestIds);

        assertApproxEqAbs(statuses[0].amountOfShares, 5e18, 1);

        assertEq(statuses[0].amountOfSTETH, expectedStETHWithdrawal);
        assertEq(statuses[0].owner,         address(almProxy));
        assertEq(statuses[0].timestamp,     block.timestamp);
        assertEq(statuses[0].isFinalized,   false);
        assertEq(statuses[0].isClaimed,     false);

        vm.prank(FINALIZER);
        WITHDRAW_QUEUE.finalize(requestIds[0], 300e27);

        statuses = WITHDRAW_QUEUE.getWithdrawalStatus(requestIds);

        assertEq(statuses[0].isFinalized, true);
        assertEq(statuses[0].isClaimed,   false);

        deal(address(almProxy), 1 ether); // Give the proxy a pre-existing ETH balance.

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IWSTETHFacet.WSTETHClaimWithdrawal(requestIds[0], expectedStETHWithdrawal);

        vm.prank(allocator);
        mainnetController.wsteth_claimWithdrawal(requestIds[0]);

        _assertReentrancyGuardWrittenToTwice();

        statuses = WITHDRAW_QUEUE.getWithdrawalStatus(requestIds);

        assertEq(statuses[0].isFinalized, true);
        assertEq(statuses[0].isClaimed,   true);

        assertEq(WETH.balanceOf(address(almProxy)),   1_000e18 + expectedStETHWithdrawal);
        assertEq(WSTETH.balanceOf(address(almProxy)), 1_000e18 + 818.02939539073162522e18);

        assertEq(address(almProxy).balance, 1 ether); // The pre-existing ETH remains untouched on the proxy.

        assertEq(
            WETH.balanceOf(address(almProxy)) + WSTETH.getStETHByWstETH(WSTETH.balanceOf(address(almProxy))),
            3_215.02343124117932632e18
        );
    }

}
