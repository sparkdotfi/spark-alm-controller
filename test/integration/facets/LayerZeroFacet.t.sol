// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IFacet }                  from "../../../src/facets/IFacet.sol";
import { ILayerZeroFacet }         from "../../../src/facets/layer-zero/ILayerZeroFacet.sol";

import { LayerZeroFacet } from "../../../src/facets/layer-zero/LayerZeroFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

abstract contract LayerZeroFacet_TestBase is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new LayerZeroFacet());

        vm.label(facet, "LayerZeroFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getRecipient.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("LAYER_ZERO_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "LAYER_ZERO_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

}

contract Controller_LayerZeroFacet_Admin_Tests is LayerZeroFacet_TestBase {

    /**********************************************************************************************/
    /*** setRecipient Tests                                                                     ***/
    /**********************************************************************************************/

    function test_setRecipient_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setRecipient(0, bytes32(0));
    }

    function test_setRecipient_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setRecipient(0, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setRecipient(0, bytes32(0));
    }

    function test_setRecipient() external {
        bytes32 recipient = bytes32(type(uint256).max);

        vm.expectEmit(address(controller));
        emit ILayerZeroFacet.LayerZeroRecipientSet(1, recipient);

        vm.record();

        vm.prank(admin);
        controller.setRecipient(1, recipient);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getRecipient(1), recipient);
    }

}
