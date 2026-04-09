// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IBasinFacet } from "../../../src/facets/basin/IBasinFacet.sol";
import { BasinFacet }  from "../../../src/facets/basin/BasinFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function LIMIT_BASIN_DEPOSIT() external pure returns (bytes32);

    function LIMIT_BASIN_WITHDRAW() external pure returns (bytes32);

}

abstract contract BasinFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new BasinFacet());

        vm.label(facet, "BasinFacet");

        vm.prank(facetValidator);
        factory.setValidFacet(facet, true);

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](2);

        wires[0] = IControllerLike.Wire(
            IControllerLike.LIMIT_BASIN_DEPOSIT.selector,
            IBasinFacet.LIMIT_DEPOSIT.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.LIMIT_BASIN_WITHDRAW.selector,
            IBasinFacet.LIMIT_WITHDRAW.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
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
