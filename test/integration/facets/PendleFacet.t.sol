// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPendleFacet }            from "../../../src/facets/pendle/IPendleFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey }   from "../../../src/libraries/RateLimitHelpers.sol";

import { PendleFacet } from "../../../src/facets/pendle/PendleFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getRedeemRateLimitKey(address market, address pt) external pure returns (bytes32);

    function router() external view returns (address);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_PendleFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new PendleFacet(makeAddr("router")));

        vm.label(facet, "PendleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getRedeemRateLimitKey.selector,
            IPendleFacet.getRedeemRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.router.selector,
            IPendleFacet.router.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("PENDLE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "PENDLE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroRouter() external {
        vm.expectRevert("PendleFacet/zero-router");
        new PendleFacet(address(0));
    }

    function test_constructor() external {
        address router = makeAddr("router");

        PendleFacet facet = new PendleFacet(router);

        assertEq(facet.router(), router);
    }

    /**********************************************************************************************/
    /*** Immutables Tests                                                                       ***/
    /**********************************************************************************************/

    function test_immutables() external {
        assertEq(controller.router(), makeAddr("router"));
    }

    /**********************************************************************************************/
    /*** getRedeemRateLimitKey Tests                                                            ***/
    /**********************************************************************************************/

    function test_getRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_PENDLE_PT_REDEEM");
        address market    = makeAddr("market");
        address pt        = makeAddr("pt");

        assertEq(
            controller.getRedeemRateLimitKey(market, pt),
            makeAddressAddressKey(keyPrefix, pt, market)
        );
    }

}
