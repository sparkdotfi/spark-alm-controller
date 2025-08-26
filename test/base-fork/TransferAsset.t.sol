// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id }       from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract TransferAssetBaseTest is ForkTestBase {

    address destination = makeAddr("destination");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Base.SPARK_EXECUTOR);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                foreignController.LIMIT_ASSET_TRANSFER(),
                address(usdcBase),
                destination
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

}

contract ForeignControllerTransferAssetFailureTests is TransferAssetBaseTest {

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.transferAsset(address(usdcBase), destination, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.transferAsset(makeAddr("fake-token"), destination, 1e18);
    }

    function test_transferAsset_rateLimitedBoundary() external {
        deal(address(usdcBase), address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.transferAsset(address(usdcBase), destination, 1_000_000e6 + 1);

        foreignController.transferAsset(address(usdcBase), destination, 1_000_000e6);
    }

}

contract ForeignControllerTransferAssetSuccessTests is TransferAssetBaseTest {

    function test_transferAsset() external {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);

        assertEq(usdcBase.balanceOf(address(destination)), 0);
        assertEq(usdcBase.balanceOf(address(almProxy)),    1_000_000e6);

        vm.prank(relayer);
        foreignController.transferAsset(address(usdcBase), destination, 1_000_000e6);

        assertEq(usdcBase.balanceOf(address(destination)), 1_000_000e6);
        assertEq(usdcBase.balanceOf(address(almProxy)),    0);
    }

}
