// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFarmFacet }                            from "../../../src/facets/farm/IFarmFacet.sol";
import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { FarmFacet } from "../../../src/facets/farm/FarmFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getDepositRateLimitKey(address farm, address stakingToken) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address farm) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_FarmFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new FarmFacet());

        vm.label(facet, "FarmFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IFarmFacet.getDepositRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IFarmFacet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("FARM_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "FARM_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix    = keccak256("LIMIT_FARM_DEPOSIT");
        address farm         = makeAddr("farm");
        address stakingToken = makeAddr("stakingToken");

        assertEq(
            controller.getDepositRateLimitKey(farm, stakingToken),
            makeAddressAddressKey(keyPrefix, stakingToken, farm)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_FARM_WITHDRAW");
        address farm      = makeAddr("farm");

        assertEq(controller.getWithdrawRateLimitKey(farm), makeAddressKey(keyPrefix, farm));
    }

}
