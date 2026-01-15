// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IWEETHLike, ILiquidityPool, IEETH } from "../../src/libraries/WeETHLib.sol";

import { WeEthModule } from "../../src/WeEthModule.sol";

import "./ForkTestBase.t.sol";

interface IRoleRegistry {
    function grantRole(bytes32 role, address account) external;
}

interface IWithdrawRequestNFT {
    function finalizeRequests(uint256 requestId) external;
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function isClaimed(uint256 requestId) external view returns (bool);
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
    function invalidateRequest(uint256 requestId) external;
    function roleRegistry() external view returns (address);
}

contract MainnetControllerWeETHTestBase is ForkTestBase {

    IWEETHLike weETH = IWEETHLike(Ethereum.WEETH);
    IERC20     weth  = IERC20(Ethereum.WETH);

    ILiquidityPool liquidityPool;
    
    address eETH;
    address weEthModule;

    address constant withdrawRequestNFTAdmin = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;

    function setUp() public override {
        super.setUp();

        eETH          = address(IWEETHLike(Ethereum.WEETH).eETH());
        liquidityPool = ILiquidityPool(IEETH(eETH).liquidityPool());

        weEthModule = address(new WeEthModule(Ethereum.SPARK_PROXY, address(almProxy)));
    }

    function _getBlock() internal override pure returns (uint256) {
        return 23469772; //  September 29, 2025
    }

}

contract MainnetControllerDepositToWeETHFailureTests is MainnetControllerWeETHTestBase {

    function test_depositToWeETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositToWeETH(1e18);
    }

    function test_depositToWeETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositToWeETH(1e18);
    }

    function test_depositToWeETH_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositToWeETH(1e18);
    }

    function test_depositToWeETH_rateLimitsBoundary() external {
        bytes32 key = mainnetController.LIMIT_WEETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositToWeETH(1_000e18 + 1);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);
    }

}

contract MainnetControllerDepositToWeETHTests is MainnetControllerWeETHTestBase {

    function test_depositToWeETH() external {
        bytes32 key = mainnetController.LIMIT_WEETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WEETH_DEPOSIT()), 1_000e18);

        assertEq(address(almProxy).balance,                 0);
        assertEq(weth.balanceOf(address(almProxy)),         1_000e18);
        assertEq(IERC20(eETH).balanceOf(address(almProxy)), 0);
        assertEq(weETH.balanceOf(address(almProxy)),        0);

        vm.record();

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WEETH_DEPOSIT()), 0);

        assertEq(IERC20(eETH).allowance(address(almProxy), address(weETH)), 0);

        assertEq(address(almProxy).balance,                 0);
        assertEq(weth.balanceOf(address(almProxy)),         0);
        assertEq(IERC20(eETH).balanceOf(address(almProxy)), 72.284763462584685147e18);
        assertEq(weETH.balanceOf(address(almProxy)),        860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);
    }

}

contract MainnetControllerRequestWithdrawFromWeETHFailureTests is MainnetControllerWeETHTestBase {

    function test_requestWithdrawFromWeETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestWithdrawFromWeETH(weEthModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestWithdrawFromWeETH(weEthModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestWithdrawFromWeETH(weEthModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );

        uint256 wETHLimit = ILiquidityPool(liquidityPool).amountForShare(weETH.getEETHByWeETH(500e18));

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, wETHLimit, wETHLimit / 1 days);

        deal(Ethereum.WEETH, address(almProxy), 500e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18 + 1);

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);
    }

}

contract MainnetControllerRequestWithdrawFromWeETHTests is MainnetControllerWeETHTestBase {

    function test_requestWithdrawFromWeETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  1_000e18);
        assertEq(weETH.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - ILiquidityPool(liquidityPool).amountForShare(weETH.getEETHByWeETH(500e18))
        );

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(withdrawRequestNFTAdmin);
        IWithdrawRequestNFT(withdrawRequestNFT).finalizeRequests(requestId);

        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), 538.958486729386273829e18);
    }

}

contract MainnetControllerClaimWithdrawalFromWeETHFailureTests is MainnetControllerWeETHTestBase {

    function test_claimWithdrawalFromWeETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.claimWithdrawalFromWeETH(weEthModule, 1);
    }

    function test_claimWithdrawalFromWeETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimWithdrawalFromWeETH(weEthModule, 1);
    }

    function test_claimWithdrawalFromWeETH_failsonClaimingTwice() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weEthModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(weETH.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - weETH.getEETHByWeETH(500e18)
        );

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(withdrawRequestNFTAdmin);
        IWithdrawRequestNFT(withdrawRequestNFT).finalizeRequests(requestId);

        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), 538.958486729386273829e18);

        vm.record();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weEthModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 538.958486729386273829e18);

        // Cannot claim withdrawal again
        vm.prank(relayer);
        vm.expectRevert("Request does not exist");
        mainnetController.claimWithdrawalFromWeETH(weEthModule, requestId);
    }

    function test_claimWithdrawalFromWeETH_invalidRequest() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weEthModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  1_000e18);
        assertEq(weETH.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - weETH.getEETHByWeETH(500e18)
        );

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        vm.prank(withdrawRequestNFTAdmin);
        IWithdrawRequestNFT(withdrawRequestNFT).invalidateRequest(requestId);
    
        assertEq(withdrawRequestNFT.isValid(requestId),     false);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(relayer);
        vm.expectRevert("WeEthModule/invalid-request-id");
        mainnetController.claimWithdrawalFromWeETH(weEthModule, requestId);

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);
    }

    function test_claimWithdrawalFromWeETH_requestNotFinalized() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weEthModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(weETH.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - weETH.getEETHByWeETH(500e18)
        );

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(relayer);
        vm.expectRevert("WeEthModule/request-not-finalized");
        mainnetController.claimWithdrawalFromWeETH(weEthModule, requestId);
    }

}

contract MainnetControllerClaimWithdrawalFromWeETHTests is MainnetControllerWeETHTestBase {

    function test_claimWithdrawalFromWeETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weEthModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weEthModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),   1_000e18);
        assertEq(weETH.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),         0);
        assertEq(rateLimits.getCurrentRateLimit(requestWithdrawKey), 1_000e18);

        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 860.655560103672447585e18);

        uint256 eETHReceived = weETH.getEETHByWeETH(weETH.balanceOf(address(almProxy)));

        assertEq(eETHReceived, 927.715236537415314851e18);

        assertApproxEqAbs(liquidityPool.amountForShare(eETHReceived), 1_000e18, 2);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weEthModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), 360.655560103672447585e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - weETH.getEETHByWeETH(500e18)
        );

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(withdrawRequestNFTAdmin);
        IWithdrawRequestNFT(withdrawRequestNFT).finalizeRequests(requestId);

        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), 538.958486729386273829e18);

        vm.record();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weEthModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 538.958486729386273829e18);
    }

}
