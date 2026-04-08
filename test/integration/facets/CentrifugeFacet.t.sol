// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICentrifugeFacet } from "../../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { CentrifugeFacet }  from "../../../src/facets/centrifuge/CentrifugeFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function getCentrifugeRecipient(uint16 centrifugeId) external view returns (bytes32);

}

abstract contract CentrifugeFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    bytes32 internal centrifugeRecipient1 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient1"))));
    bytes32 internal centrifugeRecipient2 = bytes32(uint256(uint160(makeAddr("centrifugeRecipient2"))));

    function setUp() external {
        controller = IControllerLike(_deploy());

        vm.startPrank(facetValidator);

        address facet = address(new CentrifugeFacet());

        vm.label(facet, "CentrifugeFacet");

        factory.setValidFacet(facet, true);

        vm.stopPrank();

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](2);

        wires[0] = IControllerLike.Wire(
            IControllerLike.setCentrifugeRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.getCentrifugeRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
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
        emit ICentrifugeFacet.CentrifugeRecipientSet({
            centrifugeId : 1,
            recipient    : centrifugeRecipient1
        });

        vm.prank(admin);
        controller.setCentrifugeRecipient(1, centrifugeRecipient1);

        assertEq(controller.getCentrifugeRecipient(1), centrifugeRecipient1);

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet({
            centrifugeId : 2,
            recipient    : centrifugeRecipient2
        });

        vm.prank(admin);
        controller.setCentrifugeRecipient(2, centrifugeRecipient2);

        assertEq(controller.getCentrifugeRecipient(2), centrifugeRecipient2);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICentrifugeFacet.CentrifugeRecipientSet({
            centrifugeId : 1,
            recipient    : centrifugeRecipient2
        });

        vm.prank(admin);
        controller.setCentrifugeRecipient(1, centrifugeRecipient2);

        assertEq(controller.getCentrifugeRecipient(1), centrifugeRecipient2);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

}
