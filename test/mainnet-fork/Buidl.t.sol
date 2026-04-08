// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { ITransferAssetFacet } from "../../src/facets/transfer-asset/ITransferAssetFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

abstract contract BUIDL_TestBase is ForkTestBase {

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    address internal buidlDeposit = makeAddr("buidlDeposit");

}

contract MainnetController_BUIDL_Deposit_Tests is BUIDL_TestBase {

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.transferAsset(Ethereum.USDC, buidlDeposit, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDC, buidlDeposit, 0);
    }

    function test_transferAsset_rateLimitsBoundary() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            buidlDeposit
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDC, buidlDeposit, 1_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDC, buidlDeposit, 1_000_000e6);
    }

    function test_transferAsset() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            buidlDeposit
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(USDC.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(USDC.balanceOf(buidlDeposit),      0);

        vm.expectEmit(address(mainnetController));
        emit ITransferAssetFacet.TransferAssetFacetTransfer({
            asset       : Ethereum.USDC,
            destination : buidlDeposit,
            amount      : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDC, buidlDeposit, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(USDC.balanceOf(address(almProxy)), 0);
        assertEq(USDC.balanceOf(buidlDeposit),      1_000_000e6);
    }

}
