// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { RateLimits } from "../../src/RateLimits.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IWithdrawalQueue {

    struct RequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool    isFinalized;
        bool    isClaimed;
    }

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (RequestStatus[] memory statuses);

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;

}

interface IWSTETH is IERC20 {

    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

}

abstract contract WSTETH_TestBase is ForkTestBase {

    IWithdrawalQueue constant withdrawQueue = IWithdrawalQueue(Ethereum.WSTETH_WITHDRAW_QUEUE);

    IERC20  constant weth   = IERC20(Ethereum.WETH);
    IWSTETH constant wsteth = IWSTETH(Ethereum.WSTETH);

    function _getBlock() internal override pure returns (uint256) {
        return 23469772; //  September 29, 2025
    }

}

contract MainnetController_DepositToWSTETH_FailureTests is WSTETH_TestBase {

    function test_depositToWstETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositToWstETH(1e18);
    }

    function test_depositToWstETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositToWstETH(1e18);
    }

    function test_depositToWstETH_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositToWstETH(1e18);
    }

    function test_depositToWstETH_rateLimitsBoundary() external {
        bytes32 key = mainnetController.LIMIT_WSTETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositToWstETH(1_000e18 + 1);

        vm.prank(relayer);
        mainnetController.depositToWstETH(1_000e18);
    }

}

contract MainnetController_DepositToWSTETH_SuccessTests is WSTETH_TestBase {

    function test_depositToWstETH() external {
        bytes32 key = mainnetController.LIMIT_WSTETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WSTETH_DEPOSIT()), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(wsteth.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.depositToWstETH(1_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WSTETH_DEPOSIT()), 0);

        assertEq(weth.balanceOf(address(almProxy)),   0);
        assertEq(wsteth.balanceOf(address(almProxy)), 823.029395390731625220e18);

        assertApproxEqAbs(wsteth.getStETHByWstETH(wsteth.balanceOf(address(almProxy))), 1_000e18, 2);
    }

}

contract MainnetController_RequestWithdrawFromWSTETH_FailureTests is WSTETH_TestBase {

    function test_requestWithdrawFromWstETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestWithdrawFromWstETH(1e18);
    }

    function test_requestWithdrawFromWstETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestWithdrawFromWstETH(1e18);
    }

    function test_requestWithdrawFromWstETH_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestWithdrawFromWstETH(1e18);
    }

    function test_requestWithdrawFromWstETH_rateLimitsBoundary() external {
        bytes32 requestWithdrawKey = mainnetController.LIMIT_WSTETH_REQUEST_WITHDRAW();

        uint256 stEthLimit = wsteth.getStETHByWstETH(500e18);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestWithdrawKey, stEthLimit, stEthLimit / 1 days);

        deal(Ethereum.WSTETH, address(almProxy), 500e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestWithdrawFromWstETH(500e18 + 1);

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWstETH(500e18);
    }

}

contract MainnetController_RequestWithdrawFromWSTETH_SuccessTests is WSTETH_TestBase {

    function test_requestWithdrawFromWstETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WSTETH_DEPOSIT();
        bytes32 requestWithdrawKey = mainnetController.LIMIT_WSTETH_REQUEST_WITHDRAW();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(wsteth.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWstETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   0);
        assertEq(wsteth.balanceOf(address(almProxy)), 823.029395390731625220e18);

        assertApproxEqAbs(wsteth.getStETHByWstETH(wsteth.balanceOf(address(almProxy))), 1_000e18, 2);

        uint256 expectedEthWithdrawal = wsteth.getStETHByWstETH(500e18);

        assertEq(expectedEthWithdrawal, 607.511715620589663161e18);

        vm.record();

        vm.prank(relayer);
        uint256[] memory requestIds = mainnetController.requestWithdrawFromWstETH(500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(wsteth.balanceOf(address(almProxy)), 323.029395390731625220e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEthWithdrawal
        );

        assertEq(requestIds.length, 1);

        IWithdrawalQueue.RequestStatus[] memory statuses = withdrawQueue.getWithdrawalStatus(requestIds);

        assertApproxEqAbs(statuses[0].amountOfShares, 500e18, 1);

        assertEq(statuses[0].amountOfStETH, expectedEthWithdrawal);
        assertEq(statuses[0].owner,         address(almProxy));
        assertEq(statuses[0].timestamp,     block.timestamp);
        assertEq(statuses[0].isFinalized,   false);
        assertEq(statuses[0].isClaimed,     false);
    }

}

contract MainnetController_ClaimWithdrawalFromWSTETH_FailureTests is WSTETH_TestBase {

    function test_claimWithdrawalFromWstETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.claimWithdrawalFromWstETH(1);
    }

    function test_claimWithdrawalFromWstETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimWithdrawalFromWstETH(1);
    }

}

contract MainnetController_ClaimWithdrawalFromWSTETH_SuccessTests is WSTETH_TestBase {

    address finalizer = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function test_claimWithdrawalFromWstETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WSTETH_DEPOSIT();
        bytes32 requestWithdrawKey = mainnetController.LIMIT_WSTETH_REQUEST_WITHDRAW();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(wsteth.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWstETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   0);
        assertEq(wsteth.balanceOf(address(almProxy)), 823.029395390731625220e18);

        assertApproxEqAbs(wsteth.getStETHByWstETH(wsteth.balanceOf(address(almProxy))), 1_000e18, 2);

        uint256 expectedEthWithdrawal = wsteth.getStETHByWstETH(5e18);

        assertEq(expectedEthWithdrawal, 6.075117156205896631e18);

        // NOTE: Requesting for a small withdrawal so that it can be finalized.
        vm.prank(relayer);
        uint256[] memory requestIds = mainnetController.requestWithdrawFromWstETH(5e18);

        assertEq(wsteth.balanceOf(address(almProxy)), 818.02939539073162522e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEthWithdrawal
        );

        assertEq(requestIds.length, 1);

        IWithdrawalQueue.RequestStatus[] memory statuses = withdrawQueue.getWithdrawalStatus(requestIds);

        assertApproxEqAbs(statuses[0].amountOfShares, 5e18, 1);

        assertEq(statuses[0].amountOfStETH, expectedEthWithdrawal);
        assertEq(statuses[0].owner,         address(almProxy));
        assertEq(statuses[0].timestamp,     block.timestamp);
        assertEq(statuses[0].isFinalized,   false);
        assertEq(statuses[0].isClaimed,     false);

        vm.prank(finalizer);
        withdrawQueue.finalize(requestIds[0], 300e27);

        statuses = withdrawQueue.getWithdrawalStatus(requestIds);

        assertEq(statuses[0].isFinalized, true);
        assertEq(statuses[0].isClaimed,   false);

        vm.record();

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWstETH(requestIds[0]);

        _assertReentrancyGuardWrittenToTwice();

        statuses = withdrawQueue.getWithdrawalStatus(requestIds);

        assertEq(statuses[0].isFinalized, true);
        assertEq(statuses[0].isClaimed,   true);

        assertEq(weth.balanceOf(address(almProxy)),   expectedEthWithdrawal);
        assertEq(wsteth.balanceOf(address(almProxy)), 818.02939539073162522e18);

        assertApproxEqAbs(
            weth.balanceOf(address(almProxy)) + wsteth.getStETHByWstETH(wsteth.balanceOf(address(almProxy))),
            1_000e18,
            2
        );
    }

}
