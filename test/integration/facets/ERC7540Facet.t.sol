// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC7540Facet }                         from "../../../src/facets/erc7540/IERC7540Facet.sol";
import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { ERC7540Facet } from "../../../src/facets/erc7540/ERC7540Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getDepositRateLimitKey(address token, address asset) external pure returns (bytes32);

    function getRedeemRateLimitKey(address token) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_ERC7540Facet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new ERC7540Facet());

        vm.label(facet, "ERC7540Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IERC7540Facet.getDepositRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getRedeemRateLimitKey.selector,
            IERC7540Facet.getRedeemRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("ERC7540_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "ERC7540_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_DEPOSIT");
        address token     = makeAddr("token");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getDepositRateLimitKey(token, asset),
            makeAddressAddressKey(keyPrefix, asset, token)
        );
    }

    /**********************************************************************************************/
    /*** getRedeemRateLimitKey Tests                                                            ***/
    /**********************************************************************************************/

    function test_getRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_REDEEM");
        address token     = makeAddr("token");

        assertEq(controller.getRedeemRateLimitKey(token), makeAddressKey(keyPrefix, token));
    }

}
