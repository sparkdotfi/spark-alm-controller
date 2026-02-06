// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract WrapAllProxyETH_TestBase is ForkTestBase {

    IERC20 weth = IERC20(Ethereum.WETH);

}

contract MainnetController_WrapAllProxyETH_FailureTests is WrapAllProxyETH_TestBase {

    function test_wrapAllProxyETH_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wrapAllProxyETH();
    }

    function test_wrapAllProxyETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.wrapAllProxyETH();
    }

}

contract MainnetController_WrapAllProxyETH_SuccessTests is WrapAllProxyETH_TestBase {

    function test_wrapAllProxyETH_zeroBalance() external {
        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 0);
    }

    function test_wrapAllProxyETH() external {
        vm.deal(address(almProxy), 1 ether);

        assertEq(address(almProxy).balance,         1 ether);
        assertEq(weth.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), 1 ether);
    }

}
