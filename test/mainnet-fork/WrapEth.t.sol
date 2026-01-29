// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import "./ForkTestBase.t.sol";

contract WrapEthTestBase is ForkTestBase {

    IERC20 weth = IERC20(Ethereum.WETH);

}

contract WrapEthFailureTests is WrapEthTestBase {

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

contract WrapEthSuccessTests is WrapEthTestBase {
    function test_wrapAllProxyETH_zeroBalance() external {
        assertEq(address(almProxy).balance, 0);

        uint256 initialWethBalance = weth.balanceOf(address(almProxy));

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(weth.balanceOf(address(almProxy)), initialWethBalance);
        assertEq(address(almProxy).balance,         0);
    }

    function test_wrapAllProxyETH() external {
        vm.deal(address(almProxy), 1 ether);

        assertEq(address(almProxy).balance, 1 ether);

        uint256 initialWethBalance = weth.balanceOf(address(almProxy));

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(weth.balanceOf(address(almProxy)), initialWethBalance + 1 ether);
    }

}