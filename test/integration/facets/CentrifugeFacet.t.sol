// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICentrifugeFacet }        from "../../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import {
    makeAddressAddressKey,
    makeAddressKey,
    makeAddressUint16AddressKey
} from "../../../src/libraries/RateLimitHelpers.sol";

import { CentrifugeFacet } from "../../../src/facets/centrifuge/CentrifugeFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function getRecipient(uint16 centrifugeId) external view returns (bytes32);

    function getDepositRateLimitKey(address token, address asset) external pure returns (bytes32);

    function getRedeemRateLimitKey(address token) external pure returns (bytes32);

    function getTransferRateLimitKey(address token, uint16 centrifugeId, address spoke)
        external
        pure
        returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_CentrifugeFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    bytes32 internal centrifugeRecipient1 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient1"))));
    bytes32 internal centrifugeRecipient2 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient2"))));

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new CentrifugeFacet());

        vm.label(facet, "CentrifugeFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            ICentrifugeFacet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getRedeemRateLimitKey.selector,
            ICentrifugeFacet.getRedeemRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.getTransferRateLimitKey.selector,
            ICentrifugeFacet.getTransferRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("CENTRIFUGE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "CENTRIFUGE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setRecipient Tests                                                                     ***/
    /**********************************************************************************************/

    function test_setRecipient_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setRecipient(1, centrifugeRecipient1);
    }

    function test_setRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setRecipient(1, centrifugeRecipient1);
    }

    function test_setRecipient_zeroAddress() external {
        vm.expectRevert("CentrifugeFacet/zero-recipient");
        vm.prank(admin);
        controller.setRecipient(1, bytes32(0));
    }

    function test_setRecipient() external {
        assertEq(controller.getRecipient(1), bytes32(0));
        assertEq(controller.getRecipient(2), bytes32(0));

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(1, centrifugeRecipient1);

        vm.prank(admin);
        controller.setRecipient(1, centrifugeRecipient1);

        assertEq(controller.getRecipient(1), centrifugeRecipient1);

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(2, centrifugeRecipient2);

        vm.prank(admin);
        controller.setRecipient(2, centrifugeRecipient2);

        assertEq(controller.getRecipient(2), centrifugeRecipient2);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(1, centrifugeRecipient2);

        vm.prank(admin);
        controller.setRecipient(1, centrifugeRecipient2);

        assertEq(controller.getRecipient(1), centrifugeRecipient2);

        _assertReentrancyGuardWrittenToTwice(address(controller));
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

    /**********************************************************************************************/
    /*** getTransferRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getTransferRateLimitKey() external {
        bytes32 keyPrefix    = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
        address token        = makeAddr("token");
        uint16  centrifugeId = 2;
        address spoke        = makeAddr("spoke");

        assertEq(
            controller.getTransferRateLimitKey(token, centrifugeId, spoke),
            makeAddressUint16AddressKey(keyPrefix, token, centrifugeId, spoke)
        );
    }

}
