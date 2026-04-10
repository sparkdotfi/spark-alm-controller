// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { PendleFacet } from "../../../src/facets/pendle/PendleFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

contract Controller_PendleFacet_Tests is Integration_TestBase {

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

}
