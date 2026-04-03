// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IFacetBase }      from "../../../src/facets/IFacetBase.sol";
import { ILayerZeroFacet } from "../../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { LayerZeroFacet }  from "../../../src/facets/layer-zero/LayerZeroFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32);

}

abstract contract LayerZeroFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        vm.startPrank(facetValidator);

        address facet = address(new LayerZeroFacet());

        vm.label(facet, "LayerZeroFacet");

        factory.setValidFacet(facet, true);

        vm.stopPrank();

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](2);

        wires[0] = IControllerLike.Wire(
            IControllerLike.setRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.getRecipient.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
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
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setRecipient(0, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
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
