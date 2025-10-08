// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IWithdrawalQueue {
    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external view returns (WithdrawalRequestStatus[] memory statuses);
    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;
}

interface IWSTETH is IERC20 {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

struct WithdrawalRequestStatus {
    uint256 amountOfStETH;
    uint256 amountOfShares;
    address owner;
    uint256 timestamp;
    bool    isFinalized;
    bool    isClaimed;
}

contract MainnetControllerWstETHTestBase is ForkTestBase {

    IWithdrawalQueue constant withdrawQueue = IWithdrawalQueue(Ethereum.WSTETH_WITHDRAW_QUEUE);

    IERC20  constant weth   = IERC20(Ethereum.WETH);
    IWSTETH constant wsteth = IWSTETH(Ethereum.WSTETH);

    function _getBlock() internal override pure returns (uint256) {
        return 23469772; //  September 29, 2025
    }

}

contract MainnetControllerDepositToWstETHFailureTests is MainnetControllerWstETHTestBase {

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

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositToWstETH(1_000e18 + 1);

        mainnetController.depositToWstETH(1_000e18);
    }

}

contract MainnetControllerDepositToWstETHTests is MainnetControllerWstETHTestBase {

    function test_depositToWstETH() external {
        bytes32 key = mainnetController.LIMIT_WSTETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WSTETH_DEPOSIT()), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(wsteth.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWstETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WSTETH_DEPOSIT()), 0);

        assertEq(weth.balanceOf(address(almProxy)),   0);
        assertEq(wsteth.balanceOf(address(almProxy)), 823.029395390731625220e18);

        assertApproxEqAbs(wsteth.getStETHByWstETH(wsteth.balanceOf(address(almProxy))), 1_000e18, 2);
    }

}

contract MainnetControllerRequestWithdrawFromWstETHFailureTests is MainnetControllerWstETHTestBase {

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

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestWithdrawFromWstETH(500e18 + 1);

        mainnetController.requestWithdrawFromWstETH(500e18);
    }

}

contract MainnetControllerRequestWithdrawFromWstETHTests is MainnetControllerWstETHTestBase {

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

        vm.prank(relayer);
        uint256[] memory requestIds = mainnetController.requestWithdrawFromWstETH(500e18);

        assertEq(wsteth.balanceOf(address(almProxy)), 323.029395390731625220e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEthWithdrawal
        );

        assertEq(requestIds.length, 1);

        WithdrawalRequestStatus[] memory statuses = withdrawQueue.getWithdrawalStatus(requestIds);

        assertApproxEqAbs(statuses[0].amountOfShares, 500e18, 1);

        assertEq(statuses[0].amountOfStETH, expectedEthWithdrawal);
        assertEq(statuses[0].owner,         address(almProxy));
        assertEq(statuses[0].timestamp,     block.timestamp);
        assertEq(statuses[0].isFinalized,   false);
        assertEq(statuses[0].isClaimed,     false);
    }

}

contract MainnetControllerClaimWithdrawalFromWstETHFailureTests is MainnetControllerWstETHTestBase {

    function test_claimWithdrawalFromWstETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimWithdrawalFromWstETH(1);
    }

}

contract MainnetControllerClaimWithdrawalFromWstETHTests is MainnetControllerWstETHTestBase {

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

        WithdrawalRequestStatus[] memory statuses = withdrawQueue.getWithdrawalStatus(requestIds);

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

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWstETH(requestIds[0]);

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
