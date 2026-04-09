// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { DAIUSDSFacet } from "../../../src/facets/dai-usds/DAIUSDSFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_DAIUSDSFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroDAI() external {
        vm.expectRevert("DAIUSDSFacet/zero-dai");
        new DAIUSDSFacet(address(0), address(0), address(0));
    }

    function test_constructor_zeroDAIUSDS() external {
        vm.expectRevert("DAIUSDSFacet/zero-daiUSDS");
        new DAIUSDSFacet(makeAddr("dai"), address(0), address(0));
    }

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("DAIUSDSFacet/zero-usds");
        new DAIUSDSFacet(makeAddr("dai"), makeAddr("daiUSDS"), address(0));
    }

    function test_constructor() external {
        address dai     = makeAddr("dai");
        address daiUSDS = makeAddr("daiUSDS");
        address usds    = makeAddr("usds");

        DAIUSDSFacet facet = new DAIUSDSFacet(dai, daiUSDS, usds);

        assertEq(facet.dai(),     dai);
        assertEq(facet.daiUSDS(), daiUSDS);
        assertEq(facet.usds(),    usds);
    }

}
