// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICentrifugeFacet }        from "../../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import {
    makeAddressKey,
    makeAddressUint16AddressKey
} from "../../../src/libraries/RateLimitHelpers.sol";

import { CentrifugeFacet } from "../../../src/facets/centrifuge/CentrifugeFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function getRecipient(uint16 centrifugeId) external view returns (bytes32);

    function getCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getClaimCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function getClaimCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](7);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getCancelDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelDepositRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.getCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelRedeemRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
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
    /*** getCancelDepositRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getCancelDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_CENTRIFUGE_CANCEL_DEPOSIT");
        address token     = makeAddr("token");

        assertEq(
            controller.getCancelDepositRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

    /**********************************************************************************************/
    /*** getClaimCancelDepositRateLimitKey Tests                                                ***/
    /**********************************************************************************************/

    function test_getClaimCancelDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_CENTRIFUGE_CLAIM_CANCEL_DEPOSIT");
        address token     = makeAddr("token");

        assertEq(
            controller.getClaimCancelDepositRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

    /**********************************************************************************************/
    /*** getCancelRedeemRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_getCancelRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_CENTRIFUGE_CANCEL_REDEEM");
        address token     = makeAddr("token");

        assertEq(
            controller.getCancelRedeemRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
    }

    /**********************************************************************************************/
    /*** getClaimCancelRedeemRateLimitKey Tests                                                 ***/
    /**********************************************************************************************/

    function test_getClaimCancelRedeemRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_CENTRIFUGE_CLAIM_CANCEL_REDEEM");
        address token     = makeAddr("token");

        assertEq(
            controller.getClaimCancelRedeemRateLimitKey(token),
            makeAddressKey(keyPrefix, token)
        );
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
