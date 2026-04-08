// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { PSMFacet } from "../../../src/facets/psm/PSMFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_PSMFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroDAI() external {
        vm.expectRevert("PSMFacet/zero-dai");
        new PSMFacet({
            dai_     : address(0),
            daiUSDS_ : address(0),
            psm_     : address(0),
            usdc_    : address(0),
            usds_    : address(0)
        });
    }

    function test_constructor_zeroDAIUSDS() external {
        vm.expectRevert("PSMFacet/zero-daiUSDS");
        new PSMFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : address(0),
            psm_     : address(0),
            usdc_    : address(0),
            usds_    : address(0)
        });
    }

    function test_constructor_zeroPSM() external {
        vm.expectRevert("PSMFacet/zero-psm");
        new PSMFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            psm_     : address(0),
            usdc_    : address(0),
            usds_    : address(0)
        });
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("PSMFacet/zero-usdc");
        new PSMFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            psm_     : makeAddr("psm"),
            usdc_    : address(0),
            usds_    : address(0)
        });
    }

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("PSMFacet/zero-usds");
        new PSMFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            psm_     : makeAddr("psm"),
            usdc_    : makeAddr("usdc"),
            usds_    : address(0)
        });
    }

    function test_constructor() external {
        PSMFacet facet = new PSMFacet({
            dai_     : makeAddr("dai"),
            daiUSDS_ : makeAddr("daiUSDS"),
            psm_     : makeAddr("psm"),
            usdc_    : makeAddr("usdc"),
            usds_    : makeAddr("usds")
        });

        assertEq(facet.dai(),     makeAddr("dai"));
        assertEq(facet.daiUSDS(), makeAddr("daiUSDS"));
        assertEq(facet.psm(),     makeAddr("psm"));
        assertEq(facet.usdc(),    makeAddr("usdc"));
        assertEq(facet.usds(),    makeAddr("usds"));
    }

}
