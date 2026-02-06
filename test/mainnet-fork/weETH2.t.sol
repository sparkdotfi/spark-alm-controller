// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";
import { RateLimits }     from "../../src/RateLimits.sol";
import { WEETHModule }    from "../../src/WEETHModule.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface ILiquidityPoolLike {

    function amountForShare(uint256 shareAmount) external view returns (uint256);

    function sharesForAmount(uint256 amount) external view returns (uint256);

    function withdrawRequestNFT() external view returns (address);

}

interface IWithdrawRequestNFTLike {

    function finalizeRequests(uint256 requestId) external;

    function getClaimableAmount(uint256 requestId) external view returns (uint256);

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);

    function invalidateRequest(uint256 requestId) external;

    function ownerOf(uint256 requestId) external view returns (address);

}

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

interface IWEETHLike is IERC20Like {

    function eETH() external view returns (address);

    function getEETHByWeETH(uint256 weethAmount) external view returns (uint256);

}

interface IEETHLike is IERC20Like {

    function liquidityPool() external view returns (address);

}

abstract contract WEETH_TestBase is ForkTestBase {

    address internal constant WITHDRAW_REQUEST_NFT_ADMIN = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;

    IEETHLike          internal eeth;
    ILiquidityPoolLike internal liquidityPool;

    address internal weethModule;

    function setUp() public override {
        super.setUp();

        eeth          = IEETHLike(address(IWEETHLike(Ethereum.WEETH).eETH()));
        liquidityPool = ILiquidityPoolLike(eeth.liquidityPool());

        weethModule = address(
            new ERC1967Proxy(
                address(new WEETHModule()),
                abi.encodeCall(
                    WEETHModule.initialize,
                    (Ethereum.SPARK_PROXY, address(almProxy))
                )
            )
        );
    }

    function _getBlock() internal override pure returns (uint256) {
        return 23469772; //  September 29, 2025
    }

    function _getMinSharesOut(uint256 amount) internal view returns (uint256) {
        return liquidityPool.sharesForAmount(amount) - 1;
    }

}

contract MainnetController_DepositToWEETH_Tests is WEETH_TestBase {

    function test_depositToWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositToWEETH(1e18, 0);
    }

    function test_depositToWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositToWEETH(1e18, 0);
    }

    function test_depositToWEETH_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositToWEETH(1e18, 0);
    }

    function test_depositToWEETH_rateLimitsBoundary() external {
        bytes32 key = mainnetController.LIMIT_WEETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18 + 1, 0);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, 0);
    }

    function test_depositToWEETH_slippageTooHighBoundary() external {
        bytes32 key = mainnetController.LIMIT_WEETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.expectRevert("WEETHLib/slippage-too-high");
        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut + 1);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);
    }

    function test_depositToWEETH() external {
        bytes32 key = mainnetController.LIMIT_WEETH_DEPOSIT();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WEETH_DEPOSIT()), 1_000e18);

        uint256 initialLiquidityPoolBalance = address(liquidityPool).balance;

        assertEq(address(almProxy).balance,                               0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(address(almProxy)),  1_000e18);
        assertEq(eeth.balanceOf(address(almProxy)),                       0);
        assertEq(IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy)), 0);
        assertEq(address(liquidityPool).balance,                          initialLiquidityPoolBalance);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 shares = mainnetController.depositToWEETH(1_000e18, minSharesOut);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WEETH_DEPOSIT()), 0);

        assertEq(eeth.allowance(address(almProxy), Ethereum.WEETH), 0);

        assertEq(shares, IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy)));

        assertEq(address(almProxy).balance,                               0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(address(almProxy)),  0);
        assertEq(IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy)), 927.715236537415314851e18);
        assertEq(address(liquidityPool).balance,                          initialLiquidityPoolBalance + 1_000e18);

        assertApproxEqAbs(eeth.balanceOf(address(almProxy)), 0, 1);

        assertApproxEqAbs(liquidityPool.amountForShare(IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy))), 1_000e18, 2);
    }

}

contract MainnetController_RequestWithdrawFromWEETH_Tests is WEETH_TestBase {

    function test_requestWithdrawFromWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestWithdrawFromWEETH(weethModule, 1e18);
    }

    function test_requestWithdrawFromWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestWithdrawFromWEETH(weethModule, 1e18);
    }

    function test_requestWithdrawFromWEETH_zeroMaxAmount() external {
        deal(Ethereum.WEETH, address(almProxy), 1e18);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.requestWithdrawFromWEETH(weethModule, 1e18);
    }

    function test_requestWithdrawFromWEETH_rateLimitsBoundary() external {
        bytes32 key = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);

        uint256 eethLimit = IWEETHLike(Ethereum.WEETH).getEETHByWeETH(500e18);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, eethLimit, eethLimit / 1 days);

        deal(Ethereum.WEETH, address(almProxy), 500e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.requestWithdrawFromWEETH(weethModule, 500e18 + 1);

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);
    }

    function test_requestWithdrawFromWEETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);

        uint256 initialWEETHBalance = IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy));

        assertEq(initialWEETHBalance, 927.715236537415314851e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy)), initialWEETHBalance - 500e18);

        uint256 expectedEETHBalance = IWEETHLike(Ethereum.WEETH).getEETHByWeETH(500e18);

        assertEq(expectedEETHBalance, 538.958486729386273830e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEETHBalance
        );

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), expectedEETHBalance - 1);  // Rounding error

        assertEq(withdrawRequestNFT.ownerOf(requestId), weethModule);
    }

}

contract MainnetController_ClaimWithdrawalFromWEETH_Tests is WEETH_TestBase {

    function test_claimWithdrawalFromWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.claimWithdrawalFromWEETH(weethModule, 1);
    }

    function test_claimWithdrawalFromWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimWithdrawalFromWEETH(weethModule, 1);
    }

    function test_claimWithdrawalFromWEETH_failsOnClaimingTwice() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);
        bytes32 claimWithdrawKey   = makeAddressKey(mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),   weethModule);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        vm.record();

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWEETH(weethModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        // Cannot claim withdrawal again
        vm.expectRevert("Request does not exist");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWEETH(weethModule, requestId);
    }

    function test_claimWithdrawalFromWEETH_invalidRequest() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);
        bytes32 claimWithdrawKey   = makeAddressKey(mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),   weethModule);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).invalidateRequest(requestId);

        vm.expectRevert("WEETHModule/invalid-request-id");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWEETH(weethModule, requestId);

        assertEq(IWEETHLike(Ethereum.WEETH).balanceOf(address(almProxy)), 427.715236537415314851e18);
    }

    function test_claimWithdrawalFromWEETH_requestNotFinalized() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);
        bytes32 claimWithdrawKey   = makeAddressKey(mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),   weethModule);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.expectRevert("WEETHModule/request-not-finalized");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWEETH(weethModule, requestId);
    }

    function test_claimWithdrawalFromWEETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = makeAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), weethModule);
        bytes32 claimWithdrawKey   = makeAddressKey(mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),   weethModule);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWEETH(1_000e18, minSharesOut);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWEETH(weethModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        uint256 eethAmount = 538.958486729386273829e18;

        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), eethAmount);

        vm.record();

        assertEq(address(almProxy).balance,                              0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(address(almProxy)), 0);
        assertEq(weethModule.balance,                                    0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(weethModule),       0);

        vm.prank(relayer);
        uint256 ethReceived = mainnetController.claimWithdrawalFromWEETH(weethModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,                              0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(address(almProxy)), eethAmount);
        assertEq(weethModule.balance,                                    0);
        assertEq(IERC20Like(Ethereum.WETH).balanceOf(weethModule),       0);
        assertEq(ethReceived,                                            eethAmount);
    }

}
