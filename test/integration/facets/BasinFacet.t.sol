// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IBasinFacet }             from "../../../src/facets/basin/IBasinFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { BasinFacet } from "../../../src/facets/basin/BasinFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function LIMIT_BASIN_DEPOSIT() external pure returns (bytes32);

    function LIMIT_BASIN_WITHDRAW() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

abstract contract BasinFacet_TestBase is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new BasinFacet());

        vm.label(facet, "BasinFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.LIMIT_BASIN_DEPOSIT.selector,
            IBasinFacet.LIMIT_DEPOSIT.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.LIMIT_BASIN_WITHDRAW.selector,
            IBasinFacet.LIMIT_WITHDRAW.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("BASIN_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "BASIN_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

}

contract Controller_BasinFacet_View_Tests is BasinFacet_TestBase {

    function test_LIMIT_BASIN_DEPOSIT() external view {
        assertEq(controller.LIMIT_BASIN_DEPOSIT(), keccak256("LIMIT_BASIN_DEPOSIT"));
    }

    function test_LIMIT_BASIN_WITHDRAW() external view {
        assertEq(controller.LIMIT_BASIN_WITHDRAW(), keccak256("LIMIT_BASIN_WITHDRAW"));
    }

}
