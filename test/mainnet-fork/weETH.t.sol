// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IWEETHLike, ILiquidityPoolLike, IEETHLike } from "../../src/libraries/WeETHLib.sol";

import { WeEthModule } from "../../src/WeEthModule.sol";

import "./ForkTestBase.t.sol";

interface IWithdrawRequestNFTLike {
    function finalizeRequests(uint256 requestId) external;
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function isClaimed(uint256 requestId) external view returns (bool);
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
    function invalidateRequest(uint256 requestId) external;
    function ownerOf(uint256 requestId) external view returns (address);
    function roleRegistry() external view returns (address);
}

contract MainnetControllerWeETHTestBase is ForkTestBase {

    IWEETHLike weETH = IWEETHLike(Ethereum.WEETH);
    IERC20     weth  = IERC20(Ethereum.WETH);

    ILiquidityPoolLike liquidityPool;

    IEETHLike eETH;

    address weETHModule;

    address constant WITHDRAW_REQUEST_NFT_ADMIN = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;

    function setUp() public override {
        super.setUp();

        eETH          = IEETHLike(address(IWEETHLike(Ethereum.WEETH).eETH()));
        liquidityPool = ILiquidityPoolLike(IEETHLike(eETH).liquidityPool());

        weETHModule = address(
                new ERC1967Proxy(
                    address(new WeEthModule()),
                    abi.encodeCall(
                        WeEthModule.initialize,
                        (Ethereum.SPARK_PROXY, address(almProxy))
                    )
                )
            );
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

        uint256 initialLiquidityPoolBalance = address(liquidityPool).balance;

        assertEq(address(almProxy).balance,          0);
        assertEq(weth.balanceOf(address(almProxy)),  1_000e18);
        assertEq(eETH.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 0);
        assertEq(address(liquidityPool).balance,     initialLiquidityPoolBalance);

        vm.record();

        vm.prank(relayer);
        uint256 shares = mainnetController.depositToWeETH(1_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(mainnetController.LIMIT_WEETH_DEPOSIT()), 0);

        assertEq(eETH.allowance(address(almProxy), address(weETH)), 0);

        assertEq(shares, weETH.balanceOf(address(almProxy)));

        assertEq(address(almProxy).balance,          0);
        assertEq(weth.balanceOf(address(almProxy)),  0);
        assertEq(weETH.balanceOf(address(almProxy)), 927.715236537415314851e18);
        assertEq(address(liquidityPool).balance,     initialLiquidityPoolBalance + 1_000e18);

        assertApproxEqAbs(eETH.balanceOf(address(almProxy)),                                0,        1);
        assertApproxEqAbs(liquidityPool.amountForShare(weETH.balanceOf(address(almProxy))), 1_000e18, 2);
    }

}

contract MainnetControllerRequestWithdrawFromWeETHFailureTests is MainnetControllerWeETHTestBase {

    function test_requestWithdrawFromWeETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestWithdrawFromWeETH(weETHModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestWithdrawFromWeETH(weETHModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_zeroMaxAmount() external {
        deal(Ethereum.WEETH, address(almProxy), 1e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestWithdrawFromWeETH(weETHModule, 1e18);
    }

    function test_requestWithdrawFromWeETH_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );

        uint256 wETHLimit = weETH.getEETHByWeETH(500e18);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, wETHLimit, wETHLimit / 1 days);

        deal(Ethereum.WEETH, address(almProxy), 500e18 + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18 + 1);

        vm.prank(relayer);
        mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);
    }

}

contract MainnetControllerRequestWithdrawFromWeETHTests is MainnetControllerWeETHTestBase {

    function test_requestWithdrawFromWeETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        uint256 initialWeETHBalance = weETH.balanceOf(address(almProxy));

        assertEq(initialWeETHBalance, 927.715236537415314851e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weETH.balanceOf(address(almProxy)), initialWeETHBalance - 500e18);

        uint256 expectedEEthBalance = weETH.getEETHByWeETH(500e18);

        assertEq(expectedEEthBalance, 538.958486729386273830e18);

        assertEq(
            rateLimits.getCurrentRateLimit(requestWithdrawKey),
            1_000e18 - expectedEEthBalance
        );

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);
        
        assertEq(withdrawRequestNFT.isFinalized(requestId),        true);
        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), expectedEEthBalance - 1);  // Rounding error

        assertEq(withdrawRequestNFT.ownerOf(requestId), address(weETHModule));
    }

}

contract MainnetControllerClaimWithdrawalFromWeETHFailureTests is MainnetControllerWeETHTestBase {

    function test_claimWithdrawalFromWeETH_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.claimWithdrawalFromWeETH(weETHModule, 1);
    }

    function test_claimWithdrawalFromWeETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimWithdrawalFromWeETH(weETHModule, 1);
    }

    function test_claimWithdrawalFromWeETH_failsOnClaimingTwice() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weETHModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        vm.record();

        vm.prank(relayer);
        mainnetController.claimWithdrawalFromWeETH(weETHModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        // Cannot claim withdrawal again
        vm.prank(relayer);
        vm.expectRevert("Request does not exist");
        mainnetController.claimWithdrawalFromWeETH(weETHModule, requestId);
    }

    function test_claimWithdrawalFromWeETH_invalidRequest() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weETHModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).invalidateRequest(requestId);
    
        vm.prank(relayer);
        vm.expectRevert("WeEthModule/invalid-request-id");
        mainnetController.claimWithdrawalFromWeETH(weETHModule, requestId);

        assertEq(weETH.balanceOf(address(almProxy)), 427.715236537415314851e18);
    }

    function test_claimWithdrawalFromWeETH_requestNotFinalized() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weETHModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        assertEq(withdrawRequestNFT.isValid(requestId),     true);
        assertEq(withdrawRequestNFT.isFinalized(requestId), false);

        vm.prank(relayer);
        vm.expectRevert("WeEthModule/request-not-finalized");
        mainnetController.claimWithdrawalFromWeETH(weETHModule, requestId);
    }

}

contract MainnetControllerClaimWithdrawalFromWeETHTests is MainnetControllerWeETHTestBase {

    function test_claimWithdrawalFromWeETH() external {
        bytes32 depositKey         = mainnetController.LIMIT_WEETH_DEPOSIT();
        bytes32 requestWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_REQUEST_WITHDRAW(),
            weETHModule
        );
        bytes32 claimWithdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_WEETH_CLAIM_WITHDRAW(),
            weETHModule
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,         1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(requestWithdrawKey, 1_000e18, uint256(1_000e18) / 1 days);
        rateLimits.setRateLimitData(claimWithdrawKey,   1_000e18, uint256(1_000e18) / 1 days);
        vm.stopPrank();

        deal(Ethereum.WETH, address(almProxy), 1_000e18);

        vm.prank(relayer);
        mainnetController.depositToWeETH(1_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 requestId = mainnetController.requestWithdrawFromWeETH(weETHModule, 500e18);

        _assertReentrancyGuardWrittenToTwice();

        IWithdrawRequestNFTLike withdrawRequestNFT = IWithdrawRequestNFTLike(liquidityPool.withdrawRequestNFT());

        vm.prank(WITHDRAW_REQUEST_NFT_ADMIN);
        IWithdrawRequestNFTLike(withdrawRequestNFT).finalizeRequests(requestId);

        uint256 eEthAmount = 538.958486729386273829e18;

        assertEq(withdrawRequestNFT.getClaimableAmount(requestId), eEthAmount);

        vm.record();

        assertEq(address(almProxy).balance,            0);
        assertEq(weth.balanceOf(address(almProxy)),    0);
        assertEq(address(weETHModule).balance,         0);
        assertEq(weth.balanceOf(address(weETHModule)), 0);

        vm.prank(relayer);
        uint256 ethReceived = mainnetController.claimWithdrawalFromWeETH(weETHModule, requestId);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,            0);
        assertEq(weth.balanceOf(address(almProxy)),    eEthAmount);
        assertEq(address(weETHModule).balance,         0);
        assertEq(weth.balanceOf(address(weETHModule)), 0);
        assertEq(ethReceived,                          eEthAmount);
    }

}
