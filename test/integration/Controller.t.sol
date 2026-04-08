// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController } from "../../src/interfaces/IController.sol";

import { Controller_TestBase } from "./TestBase.t.sol";

contract MockFacet1 {

    function divideBy2(uint256 arg) external pure returns (uint256) {
        return arg / 2;
    }

    function multiplyBy2(uint256 arg) external pure returns (uint256) {
        return arg * 2;
    }

}

contract MockFacet2 {

    function divideBy4(uint256 arg) external pure returns (uint256) {
        return arg / 4;
    }

    function multiplyBy4(uint256 arg) external pure returns (uint256) {
        return arg * 4;
    }

}

interface IMockController is IController {

    function div(uint256 arg) external pure returns (uint256);

    function mul(uint256 arg) external pure returns (uint256);

}

contract ControllerIntegration_Tests is Controller_TestBase {

    IMockController internal controller;

    function setUp() external {
        controller = IMockController(_deploy());
    }

    /**********************************************************************************************/
    /*** addWire Tests                                                                          ***/
    /**********************************************************************************************/

    function test_addWire_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.addWire(address(0), IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire_notValidFacet() external {
        address facet = makeAddr("facet");

        vm.expectRevert(abi.encodeWithSelector(IController.InvalidFacet.selector, facet));
        vm.prank(admin);
        controller.addWire(facet, IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire() external {
        address facet = address(new MockFacet1());

        bytes4 callSelector     = 0x12345678;
        bytes4 delegateSelector = 0x87654321;

        vm.prank(facetValidator);
        factory.setValidFacet(facet, true);

        vm.expectEmit(address(controller));
        emit IController.WireAdded({
            callSelector     : callSelector,
            delegateSelector : delegateSelector,
            facet            : facet
        });

        vm.prank(admin);
        controller.addWire(facet, IController.Wire(callSelector, delegateSelector));

        IController.Dispatch memory dispatch = controller.getDispatch(callSelector);

        assertEq(dispatch.facet,            facet);
        assertEq(dispatch.delegateSelector, delegateSelector);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector: callSelector });

        vm.prank(admin);
        controller.removeWire(callSelector);

        dispatch = controller.getDispatch(callSelector);

        assertEq(dispatch.facet,            address(0));
        assertEq(dispatch.delegateSelector, bytes4(0));
    }

    /**********************************************************************************************/
    /*** addWires Tests                                                                         ***/
    /**********************************************************************************************/

    function test_addWires_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.addWires(address(0), new IController.Wire[](0));
    }

    function test_addWires_notValidFacet() external {
        address facet = address(new MockFacet1());

        vm.expectRevert(abi.encodeWithSelector(IController.InvalidFacet.selector, facet));
        vm.prank(admin);
        controller.addWires(facet, new IController.Wire[](2));
    }

    /**********************************************************************************************/
    /*** removeWire Tests                                                                       ***/
    /**********************************************************************************************/

    function test_removeWire_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeWire(bytes4(0));
    }

    /**********************************************************************************************/
    /*** removeWires Tests                                                                      ***/
    /**********************************************************************************************/

    function test_removeWires_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeWires(new bytes4[](0));
    }

    /**********************************************************************************************/
    /*** removeAllWiresFor Tests                                                                ***/
    /**********************************************************************************************/

    function test_removeAllWiresFor_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeAllWiresFor(address(0));
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_story() external {
        address facet1 = address(new MockFacet1());
        address facet2 = address(new MockFacet2());

        address[] memory facets = new address[](2);
        facets[0] = facet1;
        facets[1] = facet2;

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = IMockController.div.selector;
        callSelectors[1] = IMockController.mul.selector;

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.div.selector
            )
        );

        controller.div(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.mul.selector
            )
        );

        controller.mul(0);

        assertEq(controller.circuits().length, 0);

        IController.Dispatch[] memory dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 2);

        assertEq(dispatches[0].facet,            address(0));
        assertEq(dispatches[0].delegateSelector, bytes4(0));
        assertEq(dispatches[1].facet,            address(0));
        assertEq(dispatches[1].delegateSelector, bytes4(0));

        IController.Wire[][] memory wirings = controller.getWirings(facets);

        assertEq(wirings.length,    2);
        assertEq(wirings[0].length, 0);
        assertEq(wirings[1].length, 0);

        vm.startPrank(facetValidator);
        factory.setValidFacet(facet1, true);
        factory.setValidFacet(facet2, true);
        vm.stopPrank();

        // Wire div to facet1.divideBy2 and mul to facet1.multiplyBy2

        IController.Wire[] memory wires = new IController.Wire[](2);
        wires[0] = IController.Wire(IMockController.div.selector, MockFacet1.divideBy2.selector);
        wires[1] = IController.Wire(IMockController.mul.selector, MockFacet1.multiplyBy2.selector);

        vm.prank(admin);
        controller.addWires(facet1, wires);

        assertEq(controller.div(12), 6);
        assertEq(controller.mul(12), 24);

        IController.Circuit[] memory circuits = controller.circuits();

        assertEq(circuits.length, 1);

        assertEq(circuits[0].facet,        facet1);
        assertEq(circuits[0].wires.length, 2);

        assertEq(circuits[0].wires[0].callSelector,     IMockController.div.selector);
        assertEq(circuits[0].wires[0].delegateSelector, MockFacet1.divideBy2.selector);
        assertEq(circuits[0].wires[1].callSelector,     IMockController.mul.selector);
        assertEq(circuits[0].wires[1].delegateSelector, MockFacet1.multiplyBy2.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 2);

        assertEq(dispatches[0].facet,            facet1);
        assertEq(dispatches[0].delegateSelector, MockFacet1.divideBy2.selector);
        assertEq(dispatches[1].facet,            facet1);
        assertEq(dispatches[1].delegateSelector, MockFacet1.multiplyBy2.selector);

        wirings = controller.getWirings(facets);

        assertEq(wirings.length, 2);

        assertEq(wirings[0].length, 2);
        assertEq(wirings[0][0].callSelector,     IMockController.div.selector);
        assertEq(wirings[0][0].delegateSelector, MockFacet1.divideBy2.selector);
        assertEq(wirings[0][1].callSelector,     IMockController.mul.selector);
        assertEq(wirings[0][1].delegateSelector, MockFacet1.multiplyBy2.selector);

        assertEq(wirings[1].length, 0);

        // Re-wire div to facet2.divideBy4 (keeping mul to facet1.multiplyBy2)

        vm.startPrank(admin);
        controller.removeWire(IMockController.div.selector);
        controller.addWire(facet2, IController.Wire(IMockController.div.selector, MockFacet2.divideBy4.selector));
        vm.stopPrank();

        assertEq(controller.div(12), 3);
        assertEq(controller.mul(12), 24);

        circuits = controller.circuits();

        assertEq(circuits.length, 2);

        assertEq(circuits[0].facet,        facet1);
        assertEq(circuits[0].wires.length, 1);

        assertEq(circuits[0].wires[0].callSelector,     IMockController.mul.selector);
        assertEq(circuits[0].wires[0].delegateSelector, MockFacet1.multiplyBy2.selector);

        assertEq(circuits[1].facet,        facet2);
        assertEq(circuits[1].wires.length, 1);

        assertEq(circuits[1].wires[0].callSelector,     IMockController.div.selector);
        assertEq(circuits[1].wires[0].delegateSelector, MockFacet2.divideBy4.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 2);

        assertEq(dispatches[0].facet,            facet2);
        assertEq(dispatches[0].delegateSelector, MockFacet2.divideBy4.selector);
        assertEq(dispatches[1].facet,            facet1);
        assertEq(dispatches[1].delegateSelector, MockFacet1.multiplyBy2.selector);

        wirings = controller.getWirings(facets);

        assertEq(wirings.length, 2);

        assertEq(wirings[0].length, 1);
        assertEq(wirings[0][0].callSelector,     IMockController.mul.selector);
        assertEq(wirings[0][0].delegateSelector, MockFacet1.multiplyBy2.selector);

        assertEq(wirings[1].length, 1);
        assertEq(wirings[1][0].callSelector,     IMockController.div.selector);
        assertEq(wirings[1][0].delegateSelector, MockFacet2.divideBy4.selector);

        // Remove all wires for facet1 and add a new wire for mul to facet2.multiplyBy4

        vm.startPrank(admin);
        controller.removeAllWiresFor(facet1);
        controller.addWire(facet2, IController.Wire(IMockController.mul.selector, MockFacet2.multiplyBy4.selector));
        vm.stopPrank();

        assertEq(controller.div(12), 3);
        assertEq(controller.mul(12), 48);

        circuits = controller.circuits();

        assertEq(circuits.length, 1);

        assertEq(circuits[0].facet,        facet2);
        assertEq(circuits[0].wires.length, 2);

        assertEq(circuits[0].wires[0].callSelector,     IMockController.div.selector);
        assertEq(circuits[0].wires[0].delegateSelector, MockFacet2.divideBy4.selector);

        assertEq(circuits[0].wires[1].callSelector,     IMockController.mul.selector);
        assertEq(circuits[0].wires[1].delegateSelector, MockFacet2.multiplyBy4.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 2);

        assertEq(dispatches[0].facet,            facet2);
        assertEq(dispatches[0].delegateSelector, MockFacet2.divideBy4.selector);
        assertEq(dispatches[1].facet,            facet2);
        assertEq(dispatches[1].delegateSelector, MockFacet2.multiplyBy4.selector);

        wirings = controller.getWirings(facets);

        assertEq(wirings.length, 2);

        assertEq(wirings[0].length, 0);

        assertEq(wirings[1].length, 2);
        assertEq(wirings[1][0].callSelector,     IMockController.div.selector);
        assertEq(wirings[1][0].delegateSelector, MockFacet2.divideBy4.selector);
        assertEq(wirings[1][1].callSelector,     IMockController.mul.selector);
        assertEq(wirings[1][1].delegateSelector, MockFacet2.multiplyBy4.selector);

        // Remove wires for div and mul

        callSelectors[0] = IMockController.div.selector;
        callSelectors[1] = IMockController.mul.selector;

        vm.prank(admin);
        controller.removeWires(callSelectors);

        circuits = controller.circuits();

        assertEq(circuits.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.div.selector
            )
        );

        controller.div(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.mul.selector
            )
        );

        controller.mul(0);

        assertEq(controller.circuits().length, 0);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 2);

        assertEq(dispatches[0].facet,            address(0));
        assertEq(dispatches[0].delegateSelector, bytes4(0));
        assertEq(dispatches[1].facet,            address(0));
        assertEq(dispatches[1].delegateSelector, bytes4(0));

        wirings = controller.getWirings(facets);

        assertEq(wirings.length,    2);
        assertEq(wirings[0].length, 0);
        assertEq(wirings[1].length, 0);
    }

}
