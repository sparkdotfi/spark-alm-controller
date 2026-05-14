// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IDAIUSDSFacet }           from "../../../src/facets/dai-usds/IDAIUSDSFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { DAIUSDSFacet } from "../../../src/facets/dai-usds/DAIUSDSFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function daiToUSDSSwapRateLimitKey() external pure returns (bytes32);

    function usdsToDAISwapRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_DAIUSDSFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new DAIUSDSFacet(
            makeAddr("dai"),
            makeAddr("daiUSDS"),
            makeAddr("usds")
        ));

        vm.label(facet, "DAIUSDSFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.daiToUSDSSwapRateLimitKey.selector,
            IDAIUSDSFacet.daiToUSDSSwapRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.usdsToDAISwapRateLimitKey.selector,
            IDAIUSDSFacet.usdsToDAISwapRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("DAIUSDS_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "DAIUSDS_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

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

    /**********************************************************************************************/
    /*** daiToUSDSSwapRateLimitKey Tests                                                        ***/
    /**********************************************************************************************/

    function test_daiToUSDSSwapRateLimitKey() external {
        assertEq(controller.daiToUSDSSwapRateLimitKey(), keccak256("LIMIT_DAIUSDS_SWAP_DAI_TO_USDS"));
    }

    /**********************************************************************************************/
    /*** usdsToDAISwapRateLimitKey Tests                                                        ***/
    /**********************************************************************************************/

    function test_usdsToDAISwapRateLimitKey() external {
        assertEq(controller.usdsToDAISwapRateLimitKey(), keccak256("LIMIT_DAIUSDS_SWAP_USDS_TO_DAI"));
    }

}
