// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl }  from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IController }             from "../../src/interfaces/IController.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";

import { Integration_TestBase } from "./TestBase.t.sol";

contract MockFacet1 {

    function div(uint256 arg) external pure returns (uint256) {
        return arg / 2;
    }

    function mul(uint256 arg) external pure returns (uint256) {
        return arg * 2;
    }

}

contract MockFacet2 {

    function div(uint256 arg) external pure returns (uint256) {
        return arg / 4;
    }

    function mul(uint256 arg) external pure returns (uint256) {
        return arg * 4;
    }

}

interface IMockController is IController {

    function divide(uint256 arg) external pure returns (uint256);

    function multiply(uint256 arg) external pure returns (uint256);

    function divideBy2(uint256 arg) external pure returns (uint256);

    function multiplyBy2(uint256 arg) external pure returns (uint256);

    function divideBy4(uint256 arg) external pure returns (uint256);

    function multiplyBy4(uint256 arg) external pure returns (uint256);

}

contract Controller_IntegrationTests is Integration_TestBase {

    IMockController internal controller;

    function setUp() external {
        controller = IMockController(_deploy());
    }

    /**********************************************************************************************/
    /*** updateIntegrations Tests                                                               ***/
    /**********************************************************************************************/

    function test_updateIntegrations_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.updateIntegrations(new bytes32[](0));
    }

    function test_updateIntegrations_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.updateIntegrations(new bytes32[](0));
    }

    function test_updateIntegrations_emptyArray() external {
        vm.expectRevert(IController.EmptyArray.selector);
        vm.prank(admin);
        controller.updateIntegrations(new bytes32[](0));
    }

    function test_updateIntegrations_integrationNotFound() external {
        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_1";

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.IntegrationNotFound.selector, integrationIds[0]));
        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    function test_updateIntegrations_callSelectorAlreadyWired() external {
        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMockController.divide.selector,   MockFacet1.div.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMockController.multiply.selector, MockFacet1.mul.selector);

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : address(new MockFacet1()),
            wires : wires
        });

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_1", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_1";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        vm.startPrank(beaconAdmin);
        beacon.removeIntegration("INTEGRATION_1");
        beacon.setIntegration("INTEGRATION_2", config);
        vm.stopPrank();

        integrationIds[0] = "INTEGRATION_2";

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnumerableIntegrations.CallSelectorAlreadyWired.selector,
                IMockController.divide.selector
            )
        );
        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    function test_updateIntegrations_callSelectorAlreadyWired_crossIntegrationSelectorMigration() external {
        address facet = address(new MockFacet1());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(0x11111111, bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(0x22222222, bytes4(0));

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_1", config);

        wires[0] = IEnumerableIntegrations.Wire(0x33333333, bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(0x44444444, bytes4(0));

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_2", IEnumerableIntegrations.Config(facet, wires));

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = "INTEGRATION_1";
        integrationIds[1] = "INTEGRATION_2";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        vm.startPrank(beaconAdmin);
        beacon.removeIntegration("INTEGRATION_1");
        beacon.removeIntegration("INTEGRATION_2");
        vm.stopPrank();

        wires[0] = IEnumerableIntegrations.Wire(0x11111111, bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(0x44444444, bytes4(0));

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_1", IEnumerableIntegrations.Config(facet, wires));

        wires[0] = IEnumerableIntegrations.Wire(0x22222222, bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(0x33333333, bytes4(0));

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_2", IEnumerableIntegrations.Config(facet, wires));

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnumerableIntegrations.CallSelectorAlreadyWired.selector,
                bytes4(0x44444444)
            )
        );

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        integrationIds[0] = "INTEGRATION_2";
        integrationIds[1] = "INTEGRATION_1";

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnumerableIntegrations.CallSelectorAlreadyWired.selector,
                bytes4(0x22222222)
            )
        );

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        vm.prank(admin);
        controller.removeIntegrations(integrationIds);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    function test_updateIntegrations() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration  = _registerTwoFactorIntegration();
        IEnumerableIntegrations.Integration memory fourFactorIntegration = _registerFourFactorIntegration();

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = fourFactorIntegration.id;

        assertEq(beacon.integrations().length,     2);
        assertEq(controller.integrations().length, 0);

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationSet(twoFactorIntegration.id, twoFactorIntegration.config);

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationSet(fourFactorIntegration.id, fourFactorIntegration.config);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        // Remove the integrations from the beacon so tests can show that they are still wired in the controller.
        vm.startPrank(beaconAdmin);
        beacon.removeIntegration(twoFactorIntegration.id);
        beacon.removeIntegration(fourFactorIntegration.id);
        vm.stopPrank();

        assertEq(beacon.integrations().length, 0);

        assertEq(controller.divideBy2(12),   6);
        assertEq(controller.multiplyBy2(12), 24);

        assertEq(controller.divideBy4(12),   3);
        assertEq(controller.multiplyBy4(12), 48);

        IEnumerableIntegrations.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 2);

        assertEq(integrations[0].config.facet,        twoFactorIntegration.config.facet);
        assertEq(integrations[0].config.wires.length, twoFactorIntegration.config.wires.length);

        assertEq(integrations[0].config.wires[0].callSelector,     twoFactorIntegration.config.wires[0].callSelector);
        assertEq(integrations[0].config.wires[0].delegateSelector, twoFactorIntegration.config.wires[0].delegateSelector);
        assertEq(integrations[0].config.wires[1].callSelector,     twoFactorIntegration.config.wires[1].callSelector);
        assertEq(integrations[0].config.wires[1].delegateSelector, twoFactorIntegration.config.wires[1].delegateSelector);

        assertEq(integrations[1].config.facet,        fourFactorIntegration.config.facet);
        assertEq(integrations[1].config.wires.length, fourFactorIntegration.config.wires.length);

        assertEq(integrations[1].config.wires[0].callSelector,     fourFactorIntegration.config.wires[0].callSelector);
        assertEq(integrations[1].config.wires[0].delegateSelector, fourFactorIntegration.config.wires[0].delegateSelector);
        assertEq(integrations[1].config.wires[1].callSelector,     fourFactorIntegration.config.wires[1].callSelector);
        assertEq(integrations[1].config.wires[1].delegateSelector, fourFactorIntegration.config.wires[1].delegateSelector);
    }

    function test_updateIntegrations_replaceExistingIntegrations() external {
        IEnumerableIntegrations.Integration memory originalIntegration = _registerTwoFactorIntegration();

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = originalIntegration.id;

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationSet(originalIntegration.id, originalIntegration.config);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        IEnumerableIntegrations.Wire[] memory newWires = new IEnumerableIntegrations.Wire[](2);
        newWires[0] = IEnumerableIntegrations.Wire(IMockController.divide.selector,   MockFacet1.div.selector);
        newWires[1] = IEnumerableIntegrations.Wire(IMockController.multiply.selector, MockFacet1.mul.selector);

        address newFacet = address(new MockFacet1());

        IEnumerableIntegrations.Config memory newConfig = IEnumerableIntegrations.Config(newFacet, newWires);

        vm.prank(beaconAdmin);
        beacon.setIntegration(originalIntegration.id, newConfig);

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationSet(originalIntegration.id, newConfig);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.divideBy2.selector));
        controller.divideBy2(12);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.multiplyBy2.selector));
        controller.multiplyBy2(12);

        assertEq(controller.divide(12),   6);
        assertEq(controller.multiply(12), 24);

        IEnumerableIntegrations.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 1);

        assertEq(integrations[0].config.facet,        newFacet);
        assertEq(integrations[0].config.wires.length, newWires.length);

        assertEq(integrations[0].config.wires[0].callSelector,     newWires[0].callSelector);
        assertEq(integrations[0].config.wires[0].delegateSelector, newWires[0].delegateSelector);
        assertEq(integrations[0].config.wires[1].callSelector,     newWires[1].callSelector);
        assertEq(integrations[0].config.wires[1].delegateSelector, newWires[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** removeIntegrations Tests                                                               ***/
    /**********************************************************************************************/

    function test_removeIntegrations_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeIntegrations(new bytes32[](0));
    }

    function test_removeIntegrations_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeIntegrations(new bytes32[](0));
    }

    function test_removeIntegrations_emptyArray() external {
        vm.expectRevert(IController.EmptyArray.selector);
        vm.prank(admin);
        controller.removeIntegrations(new bytes32[](0));
    }

    function test_removeIntegrations_integrationNotFound() external {
        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_1";

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.IntegrationNotFound.selector, integrationIds[0]));
        vm.prank(admin);
        controller.removeIntegrations(integrationIds);
    }

    function test_removeIntegrations_integrationNotFound_duplicateIds() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration = _registerTwoFactorIntegration();

        vm.prank(beaconAdmin);
        beacon.setIntegration(twoFactorIntegration.id, twoFactorIntegration.config);

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = twoFactorIntegration.id;

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.IntegrationNotFound.selector, integrationIds[0]));
        vm.prank(admin);
        controller.removeIntegrations(integrationIds);
    }

    function test_removeIntegrations() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration  = _registerTwoFactorIntegration();
        IEnumerableIntegrations.Integration memory fourFactorIntegration = _registerFourFactorIntegration();

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = fourFactorIntegration.id;

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        assertEq(controller.divideBy2(12),   6);
        assertEq(controller.multiplyBy2(12), 24);

        assertEq(controller.divideBy4(12),   3);
        assertEq(controller.multiplyBy4(12), 48);

        assertEq(beacon.integrations().length,     2);
        assertEq(controller.integrations().length, 2);

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationRemoved(integrationIds[0]);

        vm.expectEmit(address(controller));
        emit IEnumerableIntegrations.IntegrationRemoved(integrationIds[1]);

        vm.prank(admin);
        controller.removeIntegrations(integrationIds);

        assertEq(beacon.integrations().length,     2);
        assertEq(controller.integrations().length, 0);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.divideBy2.selector));
        controller.divideBy2(12);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.multiplyBy2.selector));
        controller.multiplyBy2(12);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.divideBy4.selector));
        controller.divideBy4(12);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.multiplyBy4.selector));
        controller.multiplyBy4(12);
    }

    /**********************************************************************************************/
    /*** integrations Tests                                                                     ***/
    /**********************************************************************************************/

    function test_integrations() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration  = _registerTwoFactorIntegration();
        IEnumerableIntegrations.Integration memory fourFactorIntegration = _registerFourFactorIntegration();

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = fourFactorIntegration.id;

        assertEq(controller.integrations().length, 0);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        IEnumerableIntegrations.Integration[] memory integrations = controller.integrations();
        assertEq(integrations.length, 2);

        assertEq(integrations[0].id, twoFactorIntegration.id);

        assertEq(integrations[0].config.facet,        twoFactorIntegration.config.facet);
        assertEq(integrations[0].config.wires.length, twoFactorIntegration.config.wires.length);

        assertEq(integrations[0].config.wires[0].callSelector,     twoFactorIntegration.config.wires[0].callSelector);
        assertEq(integrations[0].config.wires[0].delegateSelector, twoFactorIntegration.config.wires[0].delegateSelector);
        assertEq(integrations[0].config.wires[1].callSelector,     twoFactorIntegration.config.wires[1].callSelector);
        assertEq(integrations[0].config.wires[1].delegateSelector, twoFactorIntegration.config.wires[1].delegateSelector);

        assertEq(integrations[1].id, fourFactorIntegration.id);

        assertEq(integrations[1].config.facet,        fourFactorIntegration.config.facet);
        assertEq(integrations[1].config.wires.length, fourFactorIntegration.config.wires.length);

        assertEq(integrations[1].config.wires[0].callSelector,     fourFactorIntegration.config.wires[0].callSelector);
        assertEq(integrations[1].config.wires[0].delegateSelector, fourFactorIntegration.config.wires[0].delegateSelector);
        assertEq(integrations[1].config.wires[1].callSelector,     fourFactorIntegration.config.wires[1].callSelector);
        assertEq(integrations[1].config.wires[1].delegateSelector, fourFactorIntegration.config.wires[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** getConfig Tests                                                                        ***/
    /**********************************************************************************************/

    function test_getConfig() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration  = _registerTwoFactorIntegration();
        IEnumerableIntegrations.Integration memory fourFactorIntegration = _registerFourFactorIntegration();

        IEnumerableIntegrations.Config memory config = controller.getConfig(twoFactorIntegration.id);

        assertEq(config.facet,        address(0));
        assertEq(config.wires.length, 0);

        config = controller.getConfig(fourFactorIntegration.id);

        assertEq(config.facet,        address(0));
        assertEq(config.wires.length, 0);

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = fourFactorIntegration.id;

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        config = controller.getConfig(twoFactorIntegration.id);

        assertEq(config.facet,        twoFactorIntegration.config.facet);
        assertEq(config.wires.length, twoFactorIntegration.config.wires.length);

        assertEq(config.wires[0].callSelector,     twoFactorIntegration.config.wires[0].callSelector);
        assertEq(config.wires[0].delegateSelector, twoFactorIntegration.config.wires[0].delegateSelector);
        assertEq(config.wires[1].callSelector,     twoFactorIntegration.config.wires[1].callSelector);
        assertEq(config.wires[1].delegateSelector, twoFactorIntegration.config.wires[1].delegateSelector);

        config = controller.getConfig(fourFactorIntegration.id);

        assertEq(config.facet,        fourFactorIntegration.config.facet);
        assertEq(config.wires.length, fourFactorIntegration.config.wires.length);

        assertEq(config.wires[0].callSelector,     fourFactorIntegration.config.wires[0].callSelector);
        assertEq(config.wires[0].delegateSelector, fourFactorIntegration.config.wires[0].delegateSelector);
        assertEq(config.wires[1].callSelector,     fourFactorIntegration.config.wires[1].callSelector);
        assertEq(config.wires[1].delegateSelector, fourFactorIntegration.config.wires[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** getConfigs Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getConfigs() external {
        IEnumerableIntegrations.Integration memory twoFactorIntegration  = _registerTwoFactorIntegration();
        IEnumerableIntegrations.Integration memory fourFactorIntegration = _registerFourFactorIntegration();

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = twoFactorIntegration.id;
        integrationIds[1] = fourFactorIntegration.id;

        IEnumerableIntegrations.Config[] memory configs = controller.getConfigs(integrationIds);

        assertEq(configs.length, integrationIds.length);

        assertEq(configs[0].facet,        address(0));
        assertEq(configs[0].wires.length, 0);
        assertEq(configs[1].facet,        address(0));
        assertEq(configs[1].wires.length, 0);

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        configs = controller.getConfigs(integrationIds);

        assertEq(configs.length, integrationIds.length);

        assertEq(configs[0].facet,        twoFactorIntegration.config.facet);
        assertEq(configs[0].wires.length, twoFactorIntegration.config.wires.length);

        assertEq(configs[0].wires[0].callSelector,     twoFactorIntegration.config.wires[0].callSelector);
        assertEq(configs[0].wires[0].delegateSelector, twoFactorIntegration.config.wires[0].delegateSelector);
        assertEq(configs[0].wires[1].callSelector,     twoFactorIntegration.config.wires[1].callSelector);
        assertEq(configs[0].wires[1].delegateSelector, twoFactorIntegration.config.wires[1].delegateSelector);

        assertEq(configs[1].facet,        fourFactorIntegration.config.facet);
        assertEq(configs[1].wires.length, fourFactorIntegration.config.wires.length);

        assertEq(configs[1].wires[0].callSelector,     fourFactorIntegration.config.wires[0].callSelector);
        assertEq(configs[1].wires[0].delegateSelector, fourFactorIntegration.config.wires[0].delegateSelector);
        assertEq(configs[1].wires[1].callSelector,     fourFactorIntegration.config.wires[1].callSelector);
        assertEq(configs[1].wires[1].delegateSelector, fourFactorIntegration.config.wires[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** getDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_getDispatch() external {
        IEnumerableIntegrations.Integration memory integration = _registerTwoFactorIntegration();

        IEnumerableIntegrations.Dispatch memory dispatch = controller.getDispatch(IMockController.divideBy2.selector);

        assertEq(dispatch.facet,            address(0));
        assertEq(dispatch.delegateSelector, bytes4(0));

        dispatch = controller.getDispatch(IMockController.multiplyBy2.selector);

        assertEq(dispatch.facet,            address(0));
        assertEq(dispatch.delegateSelector, bytes4(0));

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = integration.id;

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        dispatch = controller.getDispatch(IMockController.divideBy2.selector);

        assertEq(dispatch.facet,            integration.config.facet);
        assertEq(dispatch.delegateSelector, MockFacet1.div.selector);

        dispatch = controller.getDispatch(IMockController.multiplyBy2.selector);

        assertEq(dispatch.facet,            integration.config.facet);
        assertEq(dispatch.delegateSelector, MockFacet1.mul.selector);
    }

    /**********************************************************************************************/
    /*** getDispatches Tests                                                                    ***/
    /**********************************************************************************************/

    function test_getDispatches() external {
        IEnumerableIntegrations.Integration memory integration = _registerTwoFactorIntegration();

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = IMockController.divideBy2.selector;
        callSelectors[1] = IMockController.multiplyBy2.selector;

        IEnumerableIntegrations.Dispatch[] memory dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            address(0));
        assertEq(dispatches[0].delegateSelector, bytes4(0));

        assertEq(dispatches[1].facet,            address(0));
        assertEq(dispatches[1].delegateSelector, bytes4(0));

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = integration.id;

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            integration.config.facet);
        assertEq(dispatches[0].delegateSelector, MockFacet1.div.selector);

        assertEq(dispatches[1].facet,            integration.config.facet);
        assertEq(dispatches[1].delegateSelector, MockFacet1.mul.selector);
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_story() external {
        address facet1 = address(new MockFacet1());
        address facet2 = address(new MockFacet2());

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = IMockController.divide.selector;
        callSelectors[1] = IMockController.multiply.selector;

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.divide.selector
            )
        );

        controller.divide(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.multiply.selector
            )
        );

        controller.multiply(0);

        assertEq(beacon.integrations().length,     0);
        assertEq(controller.integrations().length, 0);

        IEnumerableIntegrations.Dispatch[] memory dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            address(0));
        assertEq(dispatches[0].delegateSelector, bytes4(0));
        assertEq(dispatches[1].facet,            address(0));
        assertEq(dispatches[1].delegateSelector, bytes4(0));

        // IEnumerableIntegrations.Wire divide to facet1.div and multiply to facet1.mul

        IEnumerableIntegrations.Wire[] memory allWiresForFacet1 = new IEnumerableIntegrations.Wire[](2);
        allWiresForFacet1[0] = IEnumerableIntegrations.Wire(IMockController.divide.selector,   MockFacet1.div.selector);
        allWiresForFacet1[1] = IEnumerableIntegrations.Wire(IMockController.multiply.selector, MockFacet1.mul.selector);

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : facet1,
            wires : allWiresForFacet1
        });

        vm.prank(beaconAdmin);
        beacon.setIntegration("INTEGRATION_1", config);

        assertEq(beacon.integrations().length,     1);
        assertEq(controller.integrations().length, 0); // Unchanged as controller not yet updated.

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_1";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        assertEq(controller.divide(12), 6);
        assertEq(controller.multiply(12), 24);

        IEnumerableIntegrations.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 1); // Changed as controller updated.

        assertEq(integrations[0].config.facet,        facet1);
        assertEq(integrations[0].config.wires.length, allWiresForFacet1.length);

        assertEq(integrations[0].config.wires[0].callSelector,     IMockController.divide.selector);
        assertEq(integrations[0].config.wires[0].delegateSelector, MockFacet1.div.selector);
        assertEq(integrations[0].config.wires[1].callSelector,     IMockController.multiply.selector);
        assertEq(integrations[0].config.wires[1].delegateSelector, MockFacet1.mul.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            facet1);
        assertEq(dispatches[0].delegateSelector, MockFacet1.div.selector);
        assertEq(dispatches[1].facet,            facet1);
        assertEq(dispatches[1].delegateSelector, MockFacet1.mul.selector);

        // Re-wire divide to facet2.div (keeping multiply to facet1.mul)

        IEnumerableIntegrations.Wire[] memory multiplyWiresForFacet1 = new IEnumerableIntegrations.Wire[](1);
        multiplyWiresForFacet1[0] = IEnumerableIntegrations.Wire(IMockController.multiply.selector, MockFacet1.mul.selector);

        IEnumerableIntegrations.Wire[] memory divideWiresForFacet2 = new IEnumerableIntegrations.Wire[](1);
        divideWiresForFacet2[0] = IEnumerableIntegrations.Wire(IMockController.divide.selector, MockFacet2.div.selector);

        vm.startPrank(beaconAdmin);

        beacon.setIntegration("INTEGRATION_1", IEnumerableIntegrations.Config({
            facet : facet1,
            wires : multiplyWiresForFacet1
        }));

        beacon.setIntegration("INTEGRATION_2", IEnumerableIntegrations.Config({
            facet : facet2,
            wires : divideWiresForFacet2
        }));

        vm.stopPrank();

        assertEq(beacon.integrations().length,     2);
        assertEq(controller.integrations().length, 1); // Unchanged as controller not yet updated.

        integrationIds = new bytes32[](2);
        integrationIds[0] = "INTEGRATION_1";
        integrationIds[1] = "INTEGRATION_2";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        assertEq(controller.divide(12), 3);
        assertEq(controller.multiply(12), 24);

        integrations = controller.integrations();

        assertEq(integrations.length, 2); // Changed as controller updated.

        assertEq(integrations[0].config.facet,        facet1);
        assertEq(integrations[0].config.wires.length, 1);

        assertEq(integrations[0].config.wires[0].callSelector,     IMockController.multiply.selector);
        assertEq(integrations[0].config.wires[0].delegateSelector, MockFacet1.mul.selector);

        assertEq(integrations[1].config.facet,        facet2);
        assertEq(integrations[1].config.wires.length, 1);

        assertEq(integrations[1].config.wires[0].callSelector,     IMockController.divide.selector);
        assertEq(integrations[1].config.wires[0].delegateSelector, MockFacet2.div.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            facet2);
        assertEq(dispatches[0].delegateSelector, MockFacet2.div.selector);
        assertEq(dispatches[1].facet,            facet1);
        assertEq(dispatches[1].delegateSelector, MockFacet1.mul.selector);

        // Remove facet1 integration and route both selectors through facet2

        IEnumerableIntegrations.Wire[] memory allWiresForFacet2 = new IEnumerableIntegrations.Wire[](2);
        allWiresForFacet2[0] = IEnumerableIntegrations.Wire(IMockController.divide.selector,   MockFacet2.div.selector);
        allWiresForFacet2[1] = IEnumerableIntegrations.Wire(IMockController.multiply.selector, MockFacet2.mul.selector);

        vm.startPrank(beaconAdmin);

        beacon.removeIntegration("INTEGRATION_1");

        beacon.setIntegration("INTEGRATION_2", IEnumerableIntegrations.Config({
            facet : facet2,
            wires : allWiresForFacet2
        }));

        vm.stopPrank();

        assertEq(beacon.integrations().length,     1);
        assertEq(controller.integrations().length, 2); // Unchanged as controller not yet updated.

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.IntegrationNotFound.selector, bytes32("INTEGRATION_1")));
        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_2";

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.CallSelectorAlreadyWired.selector, IMockController.multiply.selector));
        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        integrationIds[0] = "INTEGRATION_1";

        vm.prank(admin);
        controller.removeIntegrations(integrationIds);

        assertEq(controller.integrations().length, 1); // Changed as controller updated.

        integrationIds[0] = "INTEGRATION_2";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);

        assertEq(controller.divide(12), 3);
        assertEq(controller.multiply(12), 48);

        integrations = controller.integrations();

        assertEq(integrations.length, 1); // Unchnaged as controller update did not add any new integrations.

        assertEq(integrations[0].config.facet,        facet2);
        assertEq(integrations[0].config.wires.length, allWiresForFacet2.length);

        assertEq(integrations[0].config.wires[0].callSelector,     IMockController.divide.selector);
        assertEq(integrations[0].config.wires[0].delegateSelector, MockFacet2.div.selector);

        assertEq(integrations[0].config.wires[1].callSelector,     IMockController.multiply.selector);
        assertEq(integrations[0].config.wires[1].delegateSelector, MockFacet2.mul.selector);

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            facet2);
        assertEq(dispatches[0].delegateSelector, MockFacet2.div.selector);
        assertEq(dispatches[1].facet,            facet2);
        assertEq(dispatches[1].delegateSelector, MockFacet2.mul.selector);

        vm.prank(beaconAdmin);
        beacon.removeIntegration("INTEGRATION_2");

        assertEq(beacon.integrations().length,     0);
        assertEq(controller.integrations().length, 1); // Unchanged as controller not yet updated.

        integrationIds = new bytes32[](1);
        integrationIds[0] = "INTEGRATION_2";

        vm.prank(admin);
        controller.removeIntegrations(integrationIds);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.divide.selector
            )
        );

        controller.divide(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorNotWired.selector,
                IMockController.multiply.selector
            )
        );

        controller.multiply(0);

        assertEq(controller.integrations().length, 0); // Changed as controller updated.

        dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, callSelectors.length);

        assertEq(dispatches[0].facet,            address(0));
        assertEq(dispatches[0].delegateSelector, bytes4(0));
        assertEq(dispatches[1].facet,            address(0));
        assertEq(dispatches[1].delegateSelector, bytes4(0));
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _registerTwoFactorIntegration() internal returns (IEnumerableIntegrations.Integration memory integration) {
        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMockController.divideBy2.selector,   MockFacet1.div.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMockController.multiplyBy2.selector, MockFacet1.mul.selector);

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(address(new MockFacet1()), wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("TWO_FACTOR_INTEGRATION", config);

        return IEnumerableIntegrations.Integration("TWO_FACTOR_INTEGRATION", config);
    }

    function _registerFourFactorIntegration() internal returns (IEnumerableIntegrations.Integration memory integration) {
        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMockController.divideBy4.selector,   MockFacet2.div.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMockController.multiplyBy4.selector, MockFacet2.mul.selector);

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(address(new MockFacet2()), wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("FOUR_FACTOR_INTEGRATION", config);

        return IEnumerableIntegrations.Integration("FOUR_FACTOR_INTEGRATION", config);
    }

}
