// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IWrapProxyETHFacet } from "../../src/facets/wrap-proxy-eth/IWrapProxyETHFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

contract MainnetController_WrapAllProxyETH_Tests is ForkTestBase {

    IERC20Like internal constant WETH = IERC20Like(Ethereum.WETH);

    function test_wrapAllProxyETH_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.wrapAllProxyETH();
    }

    function test_wrapAllProxyETH_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.wrapAllProxyETH();
    }

    function test_wrapAllProxyETH_zeroBalance() external {
        assertEq(address(almProxy).balance,         0);
        assertEq(WETH.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(WETH.balanceOf(address(almProxy)), 0);
    }

    function test_wrapAllProxyETH() external {
        vm.deal(address(almProxy), 1 ether);

        assertEq(address(almProxy).balance,         1 ether);
        assertEq(WETH.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IWrapProxyETHFacet.WrapProxyETHWrap({ ethAmount: 1 ether });

        vm.prank(relayer);
        mainnetController.wrapAllProxyETH();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(address(almProxy).balance,         0);
        assertEq(WETH.balanceOf(address(almProxy)), 1 ether);
    }

}
