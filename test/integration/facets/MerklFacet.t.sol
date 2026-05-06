// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IMerklFacet }             from "../../../src/facets/merkl/IMerklFacet.sol";
import { makeAddressAddressKey }   from "../../../src/libraries/RateLimitHelpers.sol";

import { MerklFacet } from "../../../src/facets/merkl/MerklFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getToggleOperatorRateLimitKey(address distributor, address operator)
        external
        pure
        returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_MerklFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new MerklFacet());

        vm.label(facet, "MerklFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getToggleOperatorRateLimitKey.selector,
            IMerklFacet.getToggleOperatorRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("MERKL_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "MERKL_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getToggleOperatorRateLimitKey Tests                                                    ***/
    /**********************************************************************************************/

    function test_getToggleOperatorRateLimitKey() external {
        bytes32 keyPrefix   = keccak256("LIMIT_MERKL_TOGGLE_OPERATOR");
        address distributor = makeAddr("distributor");
        address operator    = makeAddr("operator");

        assertEq(
            controller.getToggleOperatorRateLimitKey(distributor, operator),
            makeAddressAddressKey(keyPrefix, operator, distributor)
        );
    }

}
