// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "test/fork/ForkTestBase.t.sol";

contract EthereumControllerDepositToSNSTFailureTests is ForkTestBase {

    function test_depositToSNST_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        ethereumController.depositToSNST(1e18);
    }

    function test_depositToSNST_frozen() external {
        vm.prank(freezer);
        ethereumController.freeze();

        vm.prank(relayer);
        vm.expectRevert("EthereumController/not-active");
        ethereumController.depositToSNST(1e18);
    }

}

contract EthereumControllerDepositToSNSTTests is ForkTestBase {

    function test_depositToSNST() external {
        vm.prank(relayer);
        ethereumController.mintNST(1e18);

        assertEq(nst.balanceOf(address(almProxy)),           1e18);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               0);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        assertEq(snst.totalSupply(),                0);
        assertEq(snst.totalAssets(),                0);
        assertEq(snst.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 shares = ethereumController.depositToSNST(1e18);

        assertEq(shares, 1e18);

        assertEq(nst.balanceOf(address(almProxy)),           0);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               1e18);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        // NOTE: 1:1 exchange rate
        assertEq(snst.totalSupply(),                1e18);
        assertEq(snst.totalAssets(),                1e18);
        assertEq(snst.balanceOf(address(almProxy)), 1e18);
    }

}

contract EthereumControllerWithdrawFromSNSTFailureTests is ForkTestBase {

    function test_withdrawFromSNST_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        ethereumController.withdrawFromSNST(1e18);
    }

    function test_withdrawFromSNST_frozen() external {
        vm.prank(freezer);
        ethereumController.freeze();

        vm.prank(relayer);
        vm.expectRevert("EthereumController/not-active");
        ethereumController.withdrawFromSNST(1e18);
    }

}

contract EthereumControllerWithdrawFromSNSTTests is ForkTestBase {

    function test_withdrawFromSNST() external {
        vm.startPrank(relayer);
        ethereumController.mintNST(1e18);
        ethereumController.depositToSNST(1e18);
        vm.stopPrank();

        assertEq(nst.balanceOf(address(almProxy)),           0);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               1e18);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        // NOTE: 1:1 exchange rate
        assertEq(snst.totalSupply(),                1e18);
        assertEq(snst.totalAssets(),                1e18);
        assertEq(snst.balanceOf(address(almProxy)), 1e18);

        vm.prank(relayer);
        uint256 shares = ethereumController.withdrawFromSNST(1e18);

        assertEq(shares, 1e18);

        assertEq(nst.balanceOf(address(almProxy)),           1e18);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               0);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        assertEq(snst.totalSupply(),                0);
        assertEq(snst.totalAssets(),                0);
        assertEq(snst.balanceOf(address(almProxy)), 0);
    }

}

contract EthereumControllerRedeemFromSNSTFailureTests is ForkTestBase {

    function test_redeemFromSNST_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        ethereumController.redeemFromSNST(1e18);
    }

    function test_redeemFromSNST_frozen() external {
        vm.prank(freezer);
        ethereumController.freeze();

        vm.prank(relayer);
        vm.expectRevert("EthereumController/not-active");
        ethereumController.redeemFromSNST(1e18);
    }

}


contract EthereumControllerRedeemFromSNSTTests is ForkTestBase {

    function test_redeemFromSNST() external {
        vm.startPrank(relayer);
        ethereumController.mintNST(1e18);
        ethereumController.depositToSNST(1e18);
        vm.stopPrank();

        assertEq(nst.balanceOf(address(almProxy)),           0);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               1e18);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        // NOTE: 1:1 exchange rate
        assertEq(snst.totalSupply(),                1e18);
        assertEq(snst.totalAssets(),                1e18);
        assertEq(snst.balanceOf(address(almProxy)), 1e18);

        vm.prank(relayer);
        uint256 assets = ethereumController.redeemFromSNST(1e18);

        assertEq(assets, 1e18);

        assertEq(nst.balanceOf(address(almProxy)),           1e18);
        assertEq(nst.balanceOf(address(ethereumController)), 0);
        assertEq(nst.balanceOf(address(snst)),               0);

        assertEq(nst.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(nst.allowance(address(almProxy), address(snst)),  0);

        assertEq(snst.totalSupply(),                0);
        assertEq(snst.totalAssets(),                0);
        assertEq(snst.balanceOf(address(almProxy)), 0);
    }

}


