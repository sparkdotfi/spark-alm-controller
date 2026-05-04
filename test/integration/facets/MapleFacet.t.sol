// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IMapleFacet }             from "../../../src/facets/maple/IMapleFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressKey }          from "../../../src/libraries/RateLimitHelpers.sol";

import { MapleFacet } from "../../../src/facets/maple/MapleFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getRedeemRateLimitKey(address mapleToken) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_MapleFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new MapleFacet());

        vm.label(facet, "MapleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getRedeemRateLimitKey.selector,
            IMapleFacet.getRedeemRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("MAPLE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "MAPLE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getRedeemRateLimitKey Tests                                                            ***/
    /**********************************************************************************************/

    function test_getRedeemRateLimitKey() external {
        bytes32 keyPrefix  = keccak256("LIMIT_MAPLE_REDEEM");
        address mapleToken = makeAddr("mapleToken");

        assertEq(controller.getRedeemRateLimitKey(mapleToken), makeAddressKey(keyPrefix, mapleToken));
    }

}
