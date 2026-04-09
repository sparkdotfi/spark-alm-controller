// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { PSM3Facet } from "../../../src/facets/psm3/PSM3Facet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_PSM3Facet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroPSM() external {
        vm.expectRevert("PSM3Facet/zero-psm");
        new PSM3Facet(address(0));
    }

    function test_constructor() external {
        address psm = makeAddr("psm");

        PSM3Facet facet = new PSM3Facet(psm);

        assertEq(facet.psm(), psm);
    }

}
