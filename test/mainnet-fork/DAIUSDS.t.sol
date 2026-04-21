// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IDAIUSDSFacet } from "../../src/facets/dai-usds/IDAIUSDSFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

abstract contract DaiUsds_TestBase is ForkTestBase {

    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    function setUp() public override {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUSDSVault(vault);
    }

}

contract MainnetController_DAIUSDS_SwapUSDSToDAI_Tests is DaiUsds_TestBase {

    function test_swapUSDSToDAI_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

    function test_swapUSDSToDAI() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IDAIUSDSFacet.DAIUSDSSwapUSDSToDAI(1_000_000e18);

        vm.prank(relayer);
        mainnetController.swapUSDSToDAI(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY + 1_000_000e18);

        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
    }

}

contract MainnetController_DAIUSDS_SwapDAIToUSDS_Tests is DaiUsds_TestBase {

    function test_swapDAIToUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

    function test_swapDAIToUSDS() external {
        deal(address(dai), address(almProxy), 1_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);  // Supply not updated on deal

        assertEq(dai.allowance(address(almProxy), Ethereum.DAI_USDS), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IDAIUSDSFacet.DAIUSDSSwapDAIToUSDS(1_000_000e18);

        vm.prank(relayer);
        mainnetController.swapDAIToUSDS(1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY - 1_000_000e18);

        assertEq(dai.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
    }

}
