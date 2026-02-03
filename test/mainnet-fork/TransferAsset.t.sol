// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressAddressKey } from "../../src/RateLimitHelpers.sol";

import { MockTokenReturnFalse } from "../mocks/Mocks.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract TransferAsset_TestBase is ForkTestBase {

    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(usdc),
                receiver
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

}

contract MainnetController_TransferAsset_Tests is TransferAsset_TestBase {

    function test_transferAsset_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);
    }

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferAsset(makeAddr("fake-token"), receiver, 1e18);
    }

    function test_transferAsset_rateLimitedBoundary() external {
        deal(address(usdc), address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);
    }

    function test_transferAsset_transferFailedOnReturnFalse() external {
        MockTokenReturnFalse token = new MockTokenReturnFalse();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(token),
                receiver
            ),
            1_000_000e18,
            uint256(1_000_000e18) / 1 days
        );

        vm.stopPrank();

        deal(address(token), address(almProxy), 1_000_000e18);

        vm.expectRevert("TransferAssetLib/transfer-failed");
        vm.prank(relayer);
        mainnetController.transferAsset(address(token), receiver, 1_000_000e18);
    }

    function test_transferAsset() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);

        vm.record();

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.balanceOf(address(receiver)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);
    }

    function test_transferAsset_successNoReturnData() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                Ethereum.USDT,
                receiver
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 1_000_000e6);

        assertEq(usdt.balanceOf(address(receiver)), 0);
        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDT, receiver, 1_000_000e6);

        assertEq(usdt.balanceOf(address(receiver)), 1_000_000e6);
        assertEq(usdt.balanceOf(address(almProxy)), 0);
    }

}
