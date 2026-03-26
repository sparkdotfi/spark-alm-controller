// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICentrifugeFacet } from "../../../src/interfaces/facets/ICentrifugeFacet.sol";
import { IController }      from "../../../src/interfaces/IController.sol";

import { CentrifugeFacet } from "../../../src/libraries/CentrifugeLib.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike is IController {

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function getCentrifugeRecipient(uint16 centrifugeId) external view returns (bytes32);

}

contract CentrifugeFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    bytes32 internal centrifugeRecipient1 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient1"))));
    bytes32 internal centrifugeRecipient2 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient2"))));

    function setUp() external {
        controller = IControllerLike(_deploy());

        // NOTE: Only wires the functions needed for the tests.
        //       If more functions are needed in future tests, they should be wired here.
        address facet = address(new CentrifugeFacet());

        vm.startPrank(admin);

        vm.label(facet, "CentrifugeFacet");

        // Controller.setCentrifugeRecipient() -> CentrifugeFacet.setRecipient()
        controller.setDispatch(
            IControllerLike.setCentrifugeRecipient.selector,
            facet,
            ICentrifugeFacet.setRecipient.selector
        );

        // Controller.getCentrifugeRecipient() -> CentrifugeFacet.getRecipient()
        controller.setDispatch(
            IControllerLike.getCentrifugeRecipient.selector,
            facet,
            ICentrifugeFacet.getRecipient.selector
        );
        vm.stopPrank();
    }

}

contract Controller_CentrifugeFacet_SetRecipient_Tests is CentrifugeFacet_TestBase {

    function test_setCentrifugeRecipient_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setCentrifugeRecipient(1, centrifugeRecipient1);
    }

    function test_setCentrifugeRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setCentrifugeRecipient(1, centrifugeRecipient1);
    }

    function test_setCentrifugeRecipient() external {
        assertEq(controller.getCentrifugeRecipient(1), bytes32(0));
        assertEq(controller.getCentrifugeRecipient(2), bytes32(0));

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(1, centrifugeRecipient1);

        vm.prank(admin);
        controller.setCentrifugeRecipient(1, centrifugeRecipient1);

        assertEq(controller.getCentrifugeRecipient(1), centrifugeRecipient1);

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(2, centrifugeRecipient2);

        vm.prank(admin);
        controller.setCentrifugeRecipient(2, centrifugeRecipient2);

        assertEq(controller.getCentrifugeRecipient(2), centrifugeRecipient2);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet(1, centrifugeRecipient2);

        vm.prank(admin);
        controller.setCentrifugeRecipient(1, centrifugeRecipient2);

        assertEq(controller.getCentrifugeRecipient(1), centrifugeRecipient2);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

}
