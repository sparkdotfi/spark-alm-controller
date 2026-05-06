// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IMapleFacet }             from "../../../src/facets/maple/IMapleFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressKey }          from "../../../src/libraries/RateLimitHelpers.sol";

import { MapleFacet } from "../../../src/facets/maple/MapleFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getCancelRedeemRateLimitKey(address mapleToken) external pure returns (bytes32 key);

    function getRequestRedeemRateLimitKey(address mapleToken) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_MapleFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new MapleFacet());

        vm.label(facet, "MapleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getCancelRedeemRateLimitKey.selector,
            IMapleFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getRequestRedeemRateLimitKey.selector,
            IMapleFacet.getRequestRedeemRateLimitKey.selector
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
    /*** getRequestRedeemRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getRequestRedeemRateLimitKey() external {
        bytes32 keyPrefix  = keccak256("LIMIT_MAPLE_REQUEST_REDEEM");
        address mapleToken = makeAddr("mapleToken");

        assertEq(controller.getRequestRedeemRateLimitKey(mapleToken), makeAddressKey(keyPrefix, mapleToken));
    }

    /**********************************************************************************************/
    /*** getCancelRedeemRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_getCancelRedeemRateLimitKey() external {
        bytes32 keyPrefix  = keccak256("LIMIT_MAPLE_CANCEL_REDEEM");
        address mapleToken = makeAddr("mapleToken");

        assertEq(controller.getCancelRedeemRateLimitKey(mapleToken), makeAddressKey(keyPrefix, mapleToken));
    }

}
