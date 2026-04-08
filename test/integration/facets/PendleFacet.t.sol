// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { PendleFacet } from "../../../src/facets/pendle/PendleFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_PendleFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroRouter() external {
        vm.expectRevert("PendleFacet/zero-router");
        new PendleFacet({ router_ : address(0) });
    }

    function test_constructor() external {
        PendleFacet facet = new PendleFacet({ router_ : makeAddr("router") });

        assertEq(facet.router(), makeAddr("router"));
    }

}
