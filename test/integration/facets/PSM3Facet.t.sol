// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPSM3Facet }              from "../../../src/facets/psm3/IPSM3Facet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressKey }          from "../../../src/libraries/RateLimitHelpers.sol";

import { PSM3Facet } from "../../../src/facets/psm3/PSM3Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getDepositRateLimitKey(address asset) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address asset) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_PSM3Facet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new PSM3Facet(makeAddr("psm")));

        vm.label(facet, "PSM3Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IPSM3Facet.getDepositRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IPSM3Facet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("PSM3_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "PSM3_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

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

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_PSM_DEPOSIT");
        address asset     = makeAddr("asset");

        assertEq(controller.getDepositRateLimitKey(asset), makeAddressKey(keyPrefix, asset));
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_PSM_WITHDRAW");
        address asset     = makeAddr("asset");

        assertEq(controller.getWithdrawRateLimitKey(asset), makeAddressKey(keyPrefix, asset));
    }

}
