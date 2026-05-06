// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC7540Facet }                         from "../../../src/facets/erc7540/IERC7540Facet.sol";
import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { ERC7540Facet } from "../../../src/facets/erc7540/ERC7540Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getRequestDepositRateLimitKey(address token, address asset) external pure returns (bytes32 key);

    function getClaimDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getRequestRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function getClaimRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_ERC7540Facet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new ERC7540Facet());

        vm.label(facet, "ERC7540Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getRequestDepositRateLimitKey.selector,
            IERC7540Facet.getRequestDepositRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimDepositRateLimitKey.selector,
            IERC7540Facet.getClaimDepositRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getRequestRedeemRateLimitKey.selector,
            IERC7540Facet.getRequestRedeemRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimRedeemRateLimitKey.selector,
            IERC7540Facet.getClaimRedeemRateLimitKey.selector
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
    /*** getRequestDepositRateLimitKey Tests                                                    ***/
    /**********************************************************************************************/

    function test_getRequestDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_REQUEST_DEPOSIT");
        address token     = makeAddr("token");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getRequestDepositRateLimitKey(token, asset),
            makeAddressAddressKey(keyPrefix, asset, token)
        );
    }

    /**********************************************************************************************/
    /*** getClaimDepositRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_getClaimDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_CLAIM_DEPOSIT");
        address token     = makeAddr("token");

        assertEq(
            controller.getClaimDepositRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

    /**********************************************************************************************/
    /*** getRequestRedeemRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getRequestRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_REQUEST_REDEEM");
        address token     = makeAddr("token");

        assertEq(
            controller.getRequestRedeemRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

    /**********************************************************************************************/
    /*** getClaimRedeemRateLimitKey Tests                                                       ***/
    /**********************************************************************************************/

    function test_getClaimRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_7540_CLAIM_REDEEM");
        address token     = makeAddr("token");

        assertEq(
            controller.getClaimRedeemRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

}
