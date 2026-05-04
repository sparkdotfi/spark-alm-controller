// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ISuperstateFacet }        from "../../../src/facets/superstate/ISuperstateFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { SuperstateFacet } from "../../../src/facets/superstate/SuperstateFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function subscribeRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_SuperstateFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new SuperstateFacet(makeAddr("usdc"), makeAddr("ustb")));

        vm.label(facet, "SuperstateFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.subscribeRateLimitKey.selector,
            ISuperstateFacet.subscribeRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("SUPERSTATE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "SUPERSTATE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("SuperstateFacet/zero-usdc");
        new SuperstateFacet(address(0), address(0));
    }

    function test_constructor_zeroUSTB() external {
        vm.expectRevert("SuperstateFacet/zero-ustb");
        new SuperstateFacet(makeAddr("usdc"), address(0));
    }

    function test_constructor() external {
        address usdc = makeAddr("usdc");
        address ustb = makeAddr("ustb");

        SuperstateFacet facet = new SuperstateFacet(usdc, ustb);

        assertEq(facet.usdc(), usdc);
        assertEq(facet.ustb(), ustb);
    }

    /**********************************************************************************************/
    /*** subscribeRateLimitKey Tests                                                            ***/
    /**********************************************************************************************/

    function test_subscribeRateLimitKey() external {
        assertEq(controller.subscribeRateLimitKey(), keccak256("LIMIT_SUPERSTATE_SUBSCRIBE"));
    }

}
