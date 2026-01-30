// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ForkTestBase, IERC20, Ethereum } from "./ForkTestBase.t.sol";

contract WrapETHTestBase is ForkTestBase {

    IERC20 weth = IERC20(Ethereum.WETH);

}

contract WrapETHFailureTests is WrapETHTestBase {

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

contract WrapETHSuccessTests is WrapETHTestBase {

    function test_wrapAllProxyETH_zeroBalance() external {
        uint256 initialWethBalance = weth.balanceOf(address(almProxy));

        assertEq(address(almProxy).balance, 0);
        assertEq(initialWethBalance,        0);

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), initialWethBalance);
    }

    function test_wrapAllProxyETH() external {
        vm.deal(address(almProxy), 1 ether);

        uint256 initialWethBalance = weth.balanceOf(address(almProxy));

        assertEq(address(almProxy).balance, 1 ether);
        assertEq(initialWethBalance,        0);

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), initialWethBalance + 1 ether);
    }

}
