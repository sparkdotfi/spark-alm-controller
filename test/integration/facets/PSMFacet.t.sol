// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPSMFacet }               from "../../../src/facets/psm/IPSMFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { PSMFacet } from "../../../src/facets/psm/PSMFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function usdsToUSDCSwapRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_PSMFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new PSMFacet(
            makeAddr("dai"),
            makeAddr("daiUSDS"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("usds")
        ));

        vm.label(facet, "PSMFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.usdsToUSDCSwapRateLimitKey.selector,
            IPSMFacet.usdsToUSDCSwapRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("PSM_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "PSM_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

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

    /**********************************************************************************************/
    /*** usdsToUSDCSwapRateLimitKey Tests                                                       ***/
    /**********************************************************************************************/

    function test_usdsToUSDCSwapRateLimitKey() external {
        assertEq(controller.usdsToUSDCSwapRateLimitKey(), keccak256("LIMIT_USDS_TO_USDC"));
    }

}
