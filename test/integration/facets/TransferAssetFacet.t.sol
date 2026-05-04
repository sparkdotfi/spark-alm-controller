// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ITransferAssetFacet }     from "../../../src/facets/transfer-asset/ITransferAssetFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey }   from "../../../src/libraries/RateLimitHelpers.sol";

import { TransferAssetFacet } from "../../../src/facets/transfer-asset/TransferAssetFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getTransferRateLimitKey(address asset, address destination) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_TransferAssetFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new TransferAssetFacet());

        vm.label(facet, "TransferAssetFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getTransferRateLimitKey.selector,
            ITransferAssetFacet.getTransferRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("TRANSFER_ASSET_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "TRANSFER_ASSET_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getTransferRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getTransferRateLimitKey() external {
        bytes32 keyPrefix   = keccak256("LIMIT_ASSET_TRANSFER");
        address asset       = makeAddr("asset");
        address destination = makeAddr("destination");

        assertEq(
            controller.getTransferRateLimitKey(asset, destination),
            makeAddressAddressKey(keyPrefix, asset, destination)
        );
    }

}
