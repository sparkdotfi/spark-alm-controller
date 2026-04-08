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
        new DAIUSDSFacet({ dai_ : address(0), daiUSDS_ : address(0), usds_ : address(0) });
    }

    function test_constructor_zeroDAIUSDS() external {
        vm.expectRevert("DAIUSDSFacet/zero-daiUSDS");
        new DAIUSDSFacet({ dai_ : makeAddr("dai"), daiUSDS_ : address(0), usds_ : address(0) });
    }

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("DAIUSDSFacet/zero-usds");
        new DAIUSDSFacet({ 
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            usds_    : address(0)
        });
    }

    function test_constructor() external {
        DAIUSDSFacet facet = new DAIUSDSFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            usds_    : makeAddr("usds")
        });

        assertEq(facet.dai(),     makeAddr("dai"));
        assertEq(facet.daiUSDS(), makeAddr("daiUSDS"));
        assertEq(facet.usds(),    makeAddr("usds"));
    }

}
