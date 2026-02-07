// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { makeAddressAddressKey } from "../../src/RateLimitHelpers.sol";

import { MockTokenReturnFalse, MockTokenReturnNull } from "../mocks/Mocks.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract TransferAsset_TestBase is ForkTestBase {

    address internal receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Base.SPARK_EXECUTOR);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                foreignController.LIMIT_ASSET_TRANSFER(),
                address(usdcBase),
                receiver
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

}

contract ForeignController_TransferAsset_Tests is TransferAsset_TestBase {

    function test_transferAsset_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.transferAsset(address(usdcBase), receiver, 1_000_000e6);
    }

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.transferAsset(address(usdcBase), receiver, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferAsset(makeAddr("fake-token"), receiver, 1e18);
    }

    function test_transferAsset_rateLimitedBoundary() external {
        deal(address(usdcBase), address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferAsset(address(usdcBase), receiver, 1_000_000e6 + 1);

        vm.prank(relayer);
        foreignController.transferAsset(address(usdcBase), receiver, 1_000_000e6);
    }

    function test_transferAsset_transferFailedOnReturnFalse() external {
        MockTokenReturnFalse token = new MockTokenReturnFalse();

        vm.startPrank(Base.SPARK_EXECUTOR);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                foreignController.LIMIT_ASSET_TRANSFER(),
                address(token),
                receiver
            ),
            1_000_000e18,
            uint256(1_000_000e18) / 1 days
        );

        vm.stopPrank();

        deal(address(token), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("TransferAssetLib/transfer-failed");
        foreignController.transferAsset(address(token), receiver, 1_000_000e18);
    }

    function test_transferAsset() external {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);

        assertEq(usdcBase.balanceOf(address(receiver)), 0);
        assertEq(usdcBase.balanceOf(address(almProxy)), 1_000_000e6);

        vm.record();

        vm.prank(relayer);
        foreignController.transferAsset(address(usdcBase), receiver, 1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdcBase.balanceOf(address(receiver)), 1_000_000e6);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
    }

    function test_transferAsset_successNoReturnData() external {
        MockTokenReturnNull token = new MockTokenReturnNull("Token", "TKN", 6);

        vm.startPrank(Base.SPARK_EXECUTOR);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                foreignController.LIMIT_ASSET_TRANSFER(),
                address(token),
                receiver
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();

        deal(address(token), address(almProxy), 1_000_000e6);

        assertEq(token.balanceOf(address(receiver)), 0);
        assertEq(token.balanceOf(address(almProxy)), 1_000_000e6);

        vm.prank(relayer);
        foreignController.transferAsset(address(token), receiver, 1_000_000e6);

        assertEq(token.balanceOf(address(receiver)), 1_000_000e6);
        assertEq(token.balanceOf(address(almProxy)), 0);
    }

}
