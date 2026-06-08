// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { INFATPrimeFacet }         from "../../../src/facets/nfat-prime/INFATPrimeFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import {
    makeAddressAddressKey,
    makeAddressKey
} from "../../../src/libraries/RateLimitHelpers.sol";

import { NFATPrimeFacet } from "../../../src/facets/nfat-prime/NFATPrimeFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getCollectRateLimitKey(address facility) external pure returns (bytes32);

    function getSubscribeRateLimitKey(address facility, address gem) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address facility) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_NFATPrimeFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new NFATPrimeFacet());

        vm.label(facet, "NFATPrimeFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getSubscribeRateLimitKey.selector,
            INFATPrimeFacet.getSubscribeRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            INFATPrimeFacet.getWithdrawRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getCollectRateLimitKey.selector,
            INFATPrimeFacet.getCollectRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("NFAT_PRIME_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "NFAT_PRIME_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getSubscribeRateLimitKey Tests                                                         ***/
    /**********************************************************************************************/

    function test_getSubscribeRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_PRIME_SUBSCRIBE");
        address facility  = makeAddr("facility");
        address gem       = makeAddr("gem");

        assertEq(
            controller.getSubscribeRateLimitKey(facility, gem),
            makeAddressAddressKey(keyPrefix, gem, facility)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_PRIME_WITHDRAW");
        address facility  = makeAddr("facility");

        assertEq(
            controller.getWithdrawRateLimitKey(facility),
            makeAddressKey(keyPrefix, facility)
        );
    }

    /**********************************************************************************************/
    /*** getCollectRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getCollectRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_PRIME_COLLECT");
        address facility  = makeAddr("facility");

        assertEq(
            controller.getCollectRateLimitKey(facility),
            makeAddressKey(keyPrefix, facility)
        );
    }

}
