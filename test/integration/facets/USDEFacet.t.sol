// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IUSDEFacet }              from "../../../src/facets/usde/IUSDEFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { USDEFacet } from "../../../src/facets/usde/USDEFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setDelegatedSignerRateLimitKey() external pure returns (bytes32);

    function removeDelegatedSignerRateLimitKey() external pure returns (bytes32);

    function mintRateLimitKey() external pure returns (bytes32);

    function burnRateLimitKey() external pure returns (bytes32);

    function cooldownRateLimitKey() external pure returns (bytes32);

    function unstakeRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_USDEFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new USDEFacet(
            makeAddr("ethenaMinter"),
            makeAddr("susde"),
            makeAddr("usdc"),
            makeAddr("usde")
        ));

        vm.label(facet, "USDEFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setDelegatedSignerRateLimitKey.selector,
            IUSDEFacet.setDelegatedSignerRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.removeDelegatedSignerRateLimitKey.selector,
            IUSDEFacet.removeDelegatedSignerRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.mintRateLimitKey.selector,
            IUSDEFacet.mintRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.burnRateLimitKey.selector,
            IUSDEFacet.burnRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.cooldownRateLimitKey.selector,
            IUSDEFacet.cooldownRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.unstakeRateLimitKey.selector,
            IUSDEFacet.unstakeRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("USDE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "USDE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroEthenaMinter() external {
        vm.expectRevert("USDEFacet/zero-ethenaMinter");
        new USDEFacet(address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroSusde() external {
        vm.expectRevert("USDEFacet/zero-susde");
        new USDEFacet(makeAddr("ethenaMinter"), address(0), address(0), address(0));
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("USDEFacet/zero-usdc");
        new USDEFacet(makeAddr("ethenaMinter"), makeAddr("susde"), address(0), address(0));
    }

    function test_constructor_zeroUSDE() external {
        vm.expectRevert("USDEFacet/zero-usde");
        new USDEFacet(makeAddr("ethenaMinter"), makeAddr("susde"), makeAddr("usdc"), address(0));
    }

    function test_constructor() external {
        address ethenaMinter = makeAddr("ethenaMinter");
        address susde        = makeAddr("susde");
        address usdc         = makeAddr("usdc");
        address usde         = makeAddr("usde");

        USDEFacet facet = new USDEFacet(ethenaMinter, susde, usdc, usde);

        assertEq(facet.ethenaMinter(), ethenaMinter);
        assertEq(facet.susde(),        susde);
        assertEq(facet.usdc(),         usdc);
        assertEq(facet.usde(),         usde);
    }

    /**********************************************************************************************/
    /*** setDelegatedSignerRateLimitKey Tests                                                    ***/
    /**********************************************************************************************/

    function test_setDelegatedSignerRateLimitKey() external {
        assertEq(controller.setDelegatedSignerRateLimitKey(), keccak256("LIMIT_SET_DELEGATED_SIGNER"));
    }

    /**********************************************************************************************/
    /*** removeDelegatedSignerRateLimitKey Tests                                                ***/
    /**********************************************************************************************/

    function test_removeDelegatedSignerRateLimitKey() external {
        assertEq(controller.removeDelegatedSignerRateLimitKey(), keccak256("LIMIT_REMOVE_DELEGATED_SIGNER"));
    }

    /**********************************************************************************************/
    /*** mintRateLimitKey Tests                                                                 ***/
    /**********************************************************************************************/

    function test_mintRateLimitKey() external {
        assertEq(controller.mintRateLimitKey(), keccak256("LIMIT_USDE_MINT"));
    }

    /**********************************************************************************************/
    /*** burnRateLimitKey Tests                                                                 ***/
    /**********************************************************************************************/

    function test_burnRateLimitKey() external {
        assertEq(controller.burnRateLimitKey(), keccak256("LIMIT_USDE_BURN"));
    }

    /**********************************************************************************************/
    /*** cooldownRateLimitKey Tests                                                             ***/
    /**********************************************************************************************/

    function test_cooldownRateLimitKey() external {
        assertEq(controller.cooldownRateLimitKey(), keccak256("LIMIT_SUSDE_COOLDOWN"));
    }

    /**********************************************************************************************/
    /*** unstakeRateLimitKey Tests                                                               ***/
    /**********************************************************************************************/

    function test_unstakeRateLimitKey() external {
        assertEq(controller.unstakeRateLimitKey(), keccak256("LIMIT_UNSTAKE"));
    }

}
