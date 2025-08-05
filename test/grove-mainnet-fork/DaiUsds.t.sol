// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

contract MainnetControllerSwapUSDSToDAIFailureTests is ForkTestBase {

    function test_swapUSDSToDAI_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapUSDSToDAI(1_000_000e18);
    }

}

contract MainnetControllerSwapUSDSToDAITests is ForkTestBase {

    function test_swapUSDSToDAI() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usds.allowance(address(almProxy), DAI_USDS), 0);

        vm.prank(relayer);
        mainnetController.swapUSDSToDAI(1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY + 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), DAI_USDS), 0);
    }

}

contract MainnetControllerSwapDAIToUSDSFailureTests is ForkTestBase {

    function test_swapDAIToUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapDAIToUSDS(1_000_000e18);
    }

}

contract MainnetControllerSwapDAIToUSDSTests is ForkTestBase {

    function test_swapDAIToUSDS() external {
        deal(address(dai), address(almProxy), 1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);  // Supply not updated on deal

        assertEq(dai.allowance(address(almProxy), DAI_USDS), 0);

        vm.prank(relayer);
        mainnetController.swapDAIToUSDS(1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY - 1_000_000e18);

        assertEq(dai.allowance(address(almProxy), DAI_USDS), 0);
    }

}

