// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

contract MainnetController_SwapUSDSToDAI_Tests is ForkTestBase {

    function test_swapUSDSToDAI_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usds.allowance(address(almProxy), Ethereum.DAI_USDS), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.swapUSDSToDAI(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY + 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
    }

}

contract MainnetController_SwapDAIToUSDS_Tests is ForkTestBase {

    function test_swapDAIToUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS() external {
        deal(address(dai), address(almProxy), 1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);  // Supply not updated on deal

        assertEq(dai.allowance(address(almProxy), Ethereum.DAI_USDS), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.swapDAIToUSDS(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY - 1_000_000e18);

        assertEq(dai.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
    }

}
