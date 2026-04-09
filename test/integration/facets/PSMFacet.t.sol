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
        new PSMFacet(address(0), address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroDAIUSDS() external {
        vm.expectRevert("PSMFacet/zero-daiUSDS");
        new PSMFacet(makeAddr("dai"), address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroPSM() external {
        vm.expectRevert("PSMFacet/zero-psm");
        new PSMFacet(makeAddr("dai"), makeAddr("daiUSDS"), address(0), address(0), address(0));
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("PSMFacet/zero-usdc");
        new PSMFacet(makeAddr("dai"), makeAddr("daiUSDS"), makeAddr("psm"), address(0), address(0));
    }

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("PSMFacet/zero-usds");
        new PSMFacet(
            makeAddr("dai"),
            makeAddr("daiUSDS"),
            makeAddr("psm"),
            makeAddr("usdc"),
            address(0)
        );
    }

    function test_constructor() external {
        address dai     = makeAddr("dai");
        address daiUSDS = makeAddr("daiUSDS");
        address psm     = makeAddr("psm");
        address usdc    = makeAddr("usdc");
        address usds    = makeAddr("usds");

        PSMFacet facet = new PSMFacet(dai, daiUSDS, psm, usdc, usds);

        assertEq(facet.dai(),     dai);
        assertEq(facet.daiUSDS(), daiUSDS);
        assertEq(facet.psm(),     psm);
        assertEq(facet.usdc(),    usdc);
        assertEq(facet.usds(),    usds);
    }

}
