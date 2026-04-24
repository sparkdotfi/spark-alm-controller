// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressAddressKey, makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { IWEETHFacet }  from "../../src/facets/weeth/IWEETHFacet.sol";
import { WEETHModule } from "../../src/facets/weeth/WEETHModule.sol";

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

    function nextRequestId() external view returns (uint32);

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

    IERC20Like internal constant WETH  = IERC20Like(Ethereum.WETH);
    IWEETHLike internal constant WEETH = IWEETHLike(Ethereum.WEETH);

    IEETHLike          internal eeth;
    ILiquidityPoolLike internal liquidityPool;

    address internal weethModule;

    function setUp() public override virtual {
        super.setUp();

        eeth          = IEETHLike(WEETH.eETH());
        liquidityPool = ILiquidityPoolLike(eeth.liquidityPool());

        weethModule = address(
            new ERC1967Proxy(
                address(new WEETHModule(Ethereum.WEETH, Ethereum.WETH)),
                abi.encodeCall(
                    WEETHModule.initialize,
                    (Ethereum.SPARK_PROXY, address(almProxy))
                )
            )
        );
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23469772; //  September 29, 2025
    }

    function _getMinSharesOut(uint256 amount) internal view returns (uint256) {
        return liquidityPool.sharesForAmount(amount) - 1;
    }

    function _getMinEETHShares(uint256 amount) internal view returns (uint256) {
        return liquidityPool.sharesForAmount(amount);
    }

}

contract MainnetController_WEETH_Deposit_Tests is WEETH_TestBase {

    bytes32 internal depositKey;

    function setUp() public override {
        super.setUp();

        depositKey = makeAddressKey(mainnetController.LIMIT_WEETH_DEPOSIT(), address(eeth));
    }

    function test_depositToWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositToWeETH(1e18, 0);
    }

    function test_depositToWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.depositToWeETH(1e18, 0);
    }

    function test_depositToWEETH_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositToWeETH(1e18, 0);
    }

    function test_depositToWEETH_rateLimitsBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18 + 1, 0);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, 0);
    }

    function test_depositToWEETH_slippageTooHighBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.expectRevert("WEETHFacet/slippage-too-high");
        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut + 1);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);
    }

    function test_depositToWEETH() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000e18, uint256(1_000e18) / 1 days);

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000e18);

        uint256 initialLiquidityPoolBalance = address(liquidityPool).balance;

        assertEq(address(almProxy).balance,          0);
        assertEq(WETH.balanceOf(address(almProxy)),  1_000e18);
        assertEq(eeth.balanceOf(address(almProxy)),  0);
        assertEq(WEETH.balanceOf(address(almProxy)), 0);
        assertEq(address(liquidityPool).balance,     initialLiquidityPoolBalance);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IWEETHFacet.WEETHDeposit(
            1_000e18,
            1_000e18 - 1, // Rounding
            927.715236537415314851e18
        );

        vm.prank(relayer);
        uint256 shares = mainnetController.depositToWeETH(1_000e18, minSharesOut);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 0);

        assertEq(eeth.allowance(address(almProxy), Ethereum.WEETH), 0);

        assertEq(shares, WEETH.balanceOf(address(almProxy)));

        assertEq(address(almProxy).balance,          0);
        assertEq(WETH.balanceOf(address(almProxy)),  0);
        assertEq(WEETH.balanceOf(address(almProxy)), 927.715236537415314851e18);
        assertEq(address(liquidityPool).balance,     initialLiquidityPoolBalance + 1_000e18);

        assertApproxEqAbs(eeth.balanceOf(address(almProxy)),                                0,        1);
        assertApproxEqAbs(liquidityPool.amountForShare(WEETH.balanceOf(address(almProxy))), 1_000e18, 2);
    }

}

contract MainnetController_WEETH_RequestWithdraw_Tests is WEETH_TestBase {

    bytes32 internal depositKey;
    bytes32 internal requestWithdrawKey;

    function setUp() public override {
        super.setUp();

        depositKey = makeAddressKey(mainnetController.LIMIT_WEETH_DEPOSIT(), address(eeth));

        requestWithdrawKey = makeAddressAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), address(eeth), weethModule);
    }

    function test_requestWithdrawFromWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestWithdrawFromWeETH(weethModule, 1e18, 0);
    }

    function test_requestWithdrawFromWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.requestWithdrawFromWeETH(weethModule, 1e18, 0);
    }

    function test_requestWithdrawFromWEETH_zeroMaxAmount() external {
        deal(Ethereum.WEETH, address(almProxy), 1e18);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(weethModule, 1e18, 0);
    }

    function test_requestWithdrawFromWEETH_rateLimitsBoundary() external {
        uint256 eethLimit = WEETH.getEETHByWeETH(500e18 - 1); // Rounding error

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(requestWithdrawKey, eethLimit, eethLimit / 1 days);

        deal(Ethereum.WEETH, address(almProxy), 500e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(weethModule, 500e18 + 1, 0);

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(weethModule, 500e18, 0);
    }

    function test_requestWithdrawFromWEETH_slippageTooHighBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        uint256 expectedEETHBalance = WEETH.getEETHByWeETH(500e18 - 1); // Rounding error

        uint256 minEETHShares = _getMinEETHShares(expectedEETHBalance);

        vm.expectRevert("WEETHFacet/slippage-too-high");
        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(
            weethModule,
            500e18,
            minEETHShares + 1
        );

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(
            weethModule,
            500e18,
            minEETHShares
        );
    }

    function test_requestWithdrawFromWEETH() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        uint256 initialWEETHBalance = WEETH.balanceOf(address(almProxy));

        assertEq(initialWEETHBalance, 927.715236537415314851e18);

        uint256 expectedEETHBalance = WEETH.getEETHByWeETH(500e18 - 1); // Rounding error

        uint256 minEETHShares = _getMinEETHShares(expectedEETHBalance);

        vm.record();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        uint32 nextRequestId = withdrawRequestNFT.nextRequestId();

        vm.expectEmit(address(mainnetController));
        emit IWEETHFacet.WEETHRequestWithdraw(
            weethModule,
            nextRequestId,
            expectedEETHBalance,
            500e18
        );

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(
            weethModule,
            500e18,
            minEETHShares
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(WEETH.balanceOf(address(almProxy)), initialWEETHBalance - 500e18);

        assertEq(expectedEETHBalance, 538.958486729386273829e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEETHBalance
        );

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), expectedEETHBalance - 1);  // Rounding error

        assertEq(withdrawRequestNFT.ownerOf(requestId), weethModule);
    }

}

contract MainnetController_WEETH_ClaimWithdrawal_Tests is WEETH_TestBase {

    bytes32 internal depositKey;
    bytes32 internal requestWithdrawKey;

    function setUp() public override {
        super.setUp();

        depositKey = makeAddressKey(mainnetController.LIMIT_WEETH_DEPOSIT(), address(eeth));

        requestWithdrawKey = makeAddressAddressKey(mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(), address(eeth), weethModule);
    }

    function test_claimWithdrawalFromWEETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.claimWithdrawalFromWeETH(weethModule, 1);
    }

    function test_claimWithdrawalFromWEETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.claimWithdrawalFromWeETH(weethModule, 1);
    }

    function test_claimWithdrawalFromWEETH_failsWhenRequestRateLimitDoesNotExist() external {
        vm.expectRevert("WEETHFacet/invalid-action");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(makeAddr("invalid-weethModule"), 1);
    }

    function test_claimWithdrawalFromWEETH_failsOnClaimingTwice() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weethModule, 500e18, 0);

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weethModule, requestId);

        // Cannot claim withdrawal again.
        vm.expectRevert("Request does not exist");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weethModule, requestId);
    }

    function test_claimWithdrawalFromWEETH_invalidRequest() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weethModule, 500e18, 0);

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).invalidateRequest(requestId);

        vm.expectRevert("WEETHModule/invalid-request-id");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weethModule, requestId);

        assertEq(WEETH.balanceOf(address(almProxy)), 427.715236537415314851e18);
    }

    function test_claimWithdrawalFromWEETH_requestNotFinalized() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weethModule, 500e18, 0);

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.expectRevert("WEETHModule/request-not-finalized");
        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weethModule, requestId);
    }

    function test_claimWithdrawalFromWEETH() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        uint256 minSharesOut = _getMinSharesOut(1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18, minSharesOut);

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weethModule, 500e18, 0);

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        uint256 eethAmount = 538.958486729386273828e18;

        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), eethAmount);

        assertEq(address(almProxy).balance,         0);
        assertEq(WETH.balanceOf(address(almProxy)), 0);
        assertEq(weethModule.balance,               0);
        assertEq(WETH.balanceOf(weethModule),       0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IWEETHFacet.WEETHClaimWithdrawal(weethModule, requestId, eethAmount);

        vm.prank(relayer);
        uint256 wethReceived = mainnetController.claimWithdrawalFromWeETH(weethModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(WETH.balanceOf(address(almProxy)), eethAmount);
        assertEq(weethModule.balance,               0);
        assertEq(WETH.balanceOf(weethModule),       0);
        assertEq(wethReceived,                      eethAmount);
    }

}
