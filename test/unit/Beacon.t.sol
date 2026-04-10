// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl }           from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";

import { EnumerableSet }   from "../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IBeacon }                 from "../../src/interfaces/IBeacon.sol";
import { IController }             from "../../src/interfaces/IController.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";

import { Beacon } from "../../src/Beacon.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract MockFacet {

    function foo() external pure returns (uint256) {
        return 1;
    }

}

contract BeaconHarness is Beacon {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    constructor(address admin) Beacon(admin) {}

    function __addIntegrationId(bytes32 id) external {
        _integrationIds.add(id);
    }

    function __removeIntegrationId(bytes32 integrationId) external {
        _integrationIds.remove(integrationId);
    }

    function __setConfig(bytes32 integrationId, IEnumerableIntegrations.Config memory config) external {
        _configs[integrationId].facet = config.facet;

        IEnumerableIntegrations.Wire[] memory wires = config.wires;

        for (uint256 i = 0; i < wires.length; ++i) {
            _configs[integrationId].wires.push(wires[i]);
        }
    }

    function __removeConfig(bytes32 integrationId) external {
        IEnumerableIntegrations.Wire[] storage wires = _configs[integrationId].wires;

        while (wires.length > 0) {
            wires.pop();
        }

        delete _configs[integrationId];
    }

    function __setDispatch(bytes4 callSelector, IEnumerableIntegrations.Dispatch memory dispatch) external {
        _dispatches[callSelector] = dispatch;
    }

    function __removeDispatch(bytes4 callSelector) external {
        delete _dispatches[callSelector];
    }

    function __getHasIntegrationId(bytes32 integrationId) external view returns (bool) {
        return _integrationIds.contains(integrationId);
    }

    function __getConfig(bytes32 integrationId) external view returns (IEnumerableIntegrations.Config memory) {
        return _configs[integrationId];
    }

    function __getDispatch(bytes4 callSelector) external view returns (IEnumerableIntegrations.Dispatch memory) {
        return _dispatches[callSelector];
    }

}

contract Beacon_Tests is UnitTestBase {

    BeaconHarness internal beacon;

    function setUp() external {
        beacon = new BeaconHarness(admin);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IBeacon.ZeroAdmin.selector);
        new BeaconHarness(address(0));
    }

    function test_constructor() external {
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, admin),     true);
        assertEq(beacon.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   admin);
        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
    }

    /**********************************************************************************************/
    /*** setIntegration Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setIntegration_reentrancy() external {
        vm.store(address(beacon), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : address(0),
            wires : new IEnumerableIntegrations.Wire[](0)
        });

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        beacon.setIntegration("SOME_INTEGRATION", config);
    }

    function test_setIntegration_notAdmin() external {
        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : address(0),
            wires : new IEnumerableIntegrations.Wire[](0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );
        vm.prank(unauthorized);
        beacon.setIntegration("SOME_INTEGRATION", config);
    }

    function test_setIntegration_zeroFacet() external {
        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : address(0),
            wires : new IEnumerableIntegrations.Wire[](0)
        });

        vm.expectRevert(IBeacon.ZeroFacet.selector);
        vm.prank(admin);
        beacon.setIntegration("SOME_INTEGRATION", config);
    }

    function test_setIntegration_emptyFacet() external {
        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : makeAddr("facet"),
            wires : new IEnumerableIntegrations.Wire[](0)
        });

        vm.expectRevert(IEnumerableIntegrations.EmptyFacet.selector);
        vm.prank(admin);
        beacon.setIntegration("SOME_INTEGRATION", config);
    }

    function test_setIntegration_emptyArray() external {
        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : address(new MockFacet()),
            wires : new IEnumerableIntegrations.Wire[](0)
        });

        vm.expectRevert(IBeacon.EmptyArray.selector);
        vm.prank(admin);
        beacon.setIntegration("SOME_INTEGRATION", config);
    }

    function test_setIntegration_callSelectorHardcoded() external {
        bytes4[] memory hardcodedCallSelectors = new bytes4[](11);
        hardcodedCallSelectors[0]  = IController.updateIntegrations.selector;
        hardcodedCallSelectors[1]  = IController.removeIntegrations.selector;
        hardcodedCallSelectors[2]  = IController.accessControls.selector;
        hardcodedCallSelectors[3]  = IController.beacon.selector;
        hardcodedCallSelectors[4]  = IController.proxy.selector;
        hardcodedCallSelectors[5]  = IController.rateLimits.selector;
        hardcodedCallSelectors[6]  = IEnumerableIntegrations.integrations.selector;
        hardcodedCallSelectors[7]  = IEnumerableIntegrations.getConfig.selector;
        hardcodedCallSelectors[8]  = IEnumerableIntegrations.getConfigs.selector;
        hardcodedCallSelectors[9]  = IEnumerableIntegrations.getDispatch.selector;
        hardcodedCallSelectors[10] = IEnumerableIntegrations.getDispatches.selector;

        address facet = address(new MockFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(0x12345678, bytes4(0));

        for (uint256 i = 0; i < hardcodedCallSelectors.length; ++i) {
            wires[1] = IEnumerableIntegrations.Wire(hardcodedCallSelectors[i], bytes4(0));

            vm.expectRevert(
                abi.encodeWithSelector(
                    IBeacon.CallSelectorHardcoded.selector,
                    wires[1]
                )
            );

            vm.prank(admin);
            beacon.setIntegration("SOME_INTEGRATION", IEnumerableIntegrations.Config(facet, wires));
        }
    }

    function test_setIntegration_callSelectorAlreadyWired() external {
        address facet        = address(new MockFacet());
        bytes4  callSelector = 0x12345678;

        beacon.__setDispatch(callSelector, IEnumerableIntegrations.Dispatch(facet, bytes4(0)));

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(callSelector, bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(0x87654321,   bytes4(0));

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.CallSelectorAlreadyWired.selector, callSelector));
        vm.prank(admin);
        beacon.setIntegration("SOME_INTEGRATION", IEnumerableIntegrations.Config(facet, wires));

        wires[0] = IEnumerableIntegrations.Wire(0x87654321,   bytes4(0));
        wires[1] = IEnumerableIntegrations.Wire(callSelector, bytes4(0));

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.CallSelectorAlreadyWired.selector, callSelector));
        vm.prank(admin);
        beacon.setIntegration("SOME_INTEGRATION", IEnumerableIntegrations.Config(facet, wires));
    }

    function test_setIntegration() external {
        bytes32 integrationId = "SOME_INTEGRATION";

        beacon.__addIntegrationId(integrationId);

        address oldFacet = address(new MockFacet());

        IEnumerableIntegrations.Wire[] memory oldWires = new IEnumerableIntegrations.Wire[](3);
        oldWires[0] = IEnumerableIntegrations.Wire(0x12345678, 0x11111111);
        oldWires[1] = IEnumerableIntegrations.Wire(0xAAAAAAAA, 0x89ABCDEF);
        oldWires[2] = IEnumerableIntegrations.Wire(0xBBBBBBBB, 0xCCCCCCCC);

        IEnumerableIntegrations.Config memory oldConfig = IEnumerableIntegrations.Config(oldFacet, oldWires);

        beacon.__setConfig(integrationId, oldConfig);

        beacon.__setDispatch(oldWires[0].callSelector, IEnumerableIntegrations.Dispatch(oldFacet, oldWires[0].delegateSelector));
        beacon.__setDispatch(oldWires[1].callSelector, IEnumerableIntegrations.Dispatch(oldFacet, oldWires[1].delegateSelector));
        beacon.__setDispatch(oldWires[2].callSelector, IEnumerableIntegrations.Dispatch(oldFacet, oldWires[2].delegateSelector));

        assertEq(beacon.__getHasIntegrationId(integrationId), true);

        IEnumerableIntegrations.Config memory storedConfig = beacon.__getConfig(integrationId);

        assertEq(storedConfig.facet,        oldFacet);
        assertEq(storedConfig.wires.length, oldWires.length);

        assertEq(storedConfig.wires[0].callSelector,     oldWires[0].callSelector);
        assertEq(storedConfig.wires[0].delegateSelector, oldWires[0].delegateSelector);

        assertEq(storedConfig.wires[1].callSelector,     oldWires[1].callSelector);
        assertEq(storedConfig.wires[1].delegateSelector, oldWires[1].delegateSelector);

        assertEq(storedConfig.wires[2].callSelector,     oldWires[2].callSelector);
        assertEq(storedConfig.wires[2].delegateSelector, oldWires[2].delegateSelector);

        assertEq(beacon.__getDispatch(oldWires[0].callSelector).facet,            oldFacet);
        assertEq(beacon.__getDispatch(oldWires[0].callSelector).delegateSelector, oldWires[0].delegateSelector);

        assertEq(beacon.__getDispatch(oldWires[1].callSelector).facet,            oldFacet);
        assertEq(beacon.__getDispatch(oldWires[1].callSelector).delegateSelector, oldWires[1].delegateSelector);

        assertEq(beacon.__getDispatch(oldWires[2].callSelector).facet,            oldFacet);
        assertEq(beacon.__getDispatch(oldWires[2].callSelector).delegateSelector, oldWires[2].delegateSelector);

        address facet = address(new MockFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(0x12345678, 0x87654321);
        wires[1] = IEnumerableIntegrations.Wire(0xFEDCBA98, 0x89ABCDEF);

        IEnumerableIntegrations.Config memory newConfig = IEnumerableIntegrations.Config(facet, wires);

        vm.record();

        vm.expectEmit(address(beacon));
        emit IEnumerableIntegrations.IntegrationSet(integrationId, newConfig);

        vm.prank(admin);
        beacon.setIntegration(integrationId, newConfig);

        _assertReentrancyGuardWrittenToTwice(address(beacon));

        assertEq(beacon.__getHasIntegrationId(integrationId), true);

        storedConfig = beacon.__getConfig(integrationId);

        assertEq(storedConfig.facet,        facet);
        assertEq(storedConfig.wires.length, wires.length);

        assertEq(storedConfig.wires[0].callSelector,     wires[0].callSelector);
        assertEq(storedConfig.wires[0].delegateSelector, wires[0].delegateSelector);

        assertEq(storedConfig.wires[1].callSelector,     wires[1].callSelector);
        assertEq(storedConfig.wires[1].delegateSelector, wires[1].delegateSelector);

        assertEq(beacon.__getDispatch(wires[0].callSelector).facet,            facet);
        assertEq(beacon.__getDispatch(wires[0].callSelector).delegateSelector, wires[0].delegateSelector);

        assertEq(beacon.__getDispatch(wires[1].callSelector).facet,            facet);
        assertEq(beacon.__getDispatch(wires[1].callSelector).delegateSelector, wires[1].delegateSelector);

        // Check old wires
        assertEq(beacon.__getDispatch(oldWires[0].callSelector).facet,            facet);
        assertEq(beacon.__getDispatch(oldWires[0].callSelector).delegateSelector, wires[0].delegateSelector);

        assertEq(beacon.__getDispatch(oldWires[1].callSelector).facet,            address(0));
        assertEq(beacon.__getDispatch(oldWires[1].callSelector).delegateSelector, bytes4(0));

        assertEq(beacon.__getDispatch(oldWires[2].callSelector).facet,            address(0));
        assertEq(beacon.__getDispatch(oldWires[2].callSelector).delegateSelector, bytes4(0));
    }

    /**********************************************************************************************/
    /*** removeIntegration Tests                                                                ***/
    /**********************************************************************************************/

    function test_removeIntegration_reentrancy() external {
        vm.store(address(beacon), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        beacon.removeIntegration("SOME_INTEGRATION");
    }

    function test_removeIntegration_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        beacon.removeIntegration("SOME_INTEGRATION");
    }

    function test_removeIntegration_integrationNotFound() external {
        bytes32 integrationId = "SOME_INTEGRATION";

        vm.expectRevert(abi.encodeWithSelector(IEnumerableIntegrations.IntegrationNotFound.selector, integrationId));
        vm.prank(admin);
        beacon.removeIntegration(integrationId);
    }

    function test_removeIntegration() external {
        bytes32 integrationId = "SOME_INTEGRATION";

        address facet = makeAddr("facet");

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;

        bytes4[] memory delegateSelectors = new bytes4[](2);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(callSelectors[0], delegateSelectors[0]);
        wires[1] = IEnumerableIntegrations.Wire(callSelectors[1], delegateSelectors[1]);

        beacon.__addIntegrationId(integrationId);

        beacon.__setConfig(integrationId, IEnumerableIntegrations.Config(facet, wires));

        beacon.__setDispatch(callSelectors[0], IEnumerableIntegrations.Dispatch(facet, delegateSelectors[0]));
        beacon.__setDispatch(callSelectors[1], IEnumerableIntegrations.Dispatch(facet, delegateSelectors[1]));

        assertEq(beacon.__getHasIntegrationId(integrationId), true);

        IEnumerableIntegrations.Config memory storedConfig = beacon.__getConfig(integrationId);

        assertEq(storedConfig.facet,        facet);
        assertEq(storedConfig.wires.length, wires.length);

        assertEq(storedConfig.wires[0].callSelector,     wires[0].callSelector);
        assertEq(storedConfig.wires[0].delegateSelector, wires[0].delegateSelector);

        assertEq(storedConfig.wires[1].callSelector,     wires[1].callSelector);
        assertEq(storedConfig.wires[1].delegateSelector, wires[1].delegateSelector);

        assertEq(beacon.__getDispatch(wires[0].callSelector).facet,            facet);
        assertEq(beacon.__getDispatch(wires[0].callSelector).delegateSelector, wires[0].delegateSelector);

        assertEq(beacon.__getDispatch(wires[1].callSelector).facet,            facet);
        assertEq(beacon.__getDispatch(wires[1].callSelector).delegateSelector, wires[1].delegateSelector);

        vm.record();

        vm.expectEmit(address(beacon));
        emit IEnumerableIntegrations.IntegrationRemoved(integrationId);

        vm.prank(admin);
        beacon.removeIntegration(integrationId);

        _assertReentrancyGuardWrittenToTwice(address(beacon));

        assertEq(beacon.__getHasIntegrationId(integrationId), false);

        storedConfig = beacon.__getConfig(integrationId);

        assertEq(storedConfig.facet,        address(0));
        assertEq(storedConfig.wires.length, 0);

        assertEq(beacon.__getDispatch(wires[0].callSelector).facet,            address(0));
        assertEq(beacon.__getDispatch(wires[0].callSelector).delegateSelector, bytes4(0));

        assertEq(beacon.__getDispatch(wires[1].callSelector).facet,            address(0));
        assertEq(beacon.__getDispatch(wires[1].callSelector).delegateSelector, bytes4(0));
    }

    /**********************************************************************************************/
    /*** integrations Tests                                                                     ***/
    /**********************************************************************************************/

    function test_integrations() external {
        bytes32 integrationId1 = "INTEGRATION_1";
        bytes32 integrationId2 = "INTEGRATION_2";

        address facet1 = makeAddr("facet1");
        address facet2 = makeAddr("facet2");

        IEnumerableIntegrations.Wire[] memory wires1 = new IEnumerableIntegrations.Wire[](1);
        wires1[0] = IEnumerableIntegrations.Wire(0x12345678, 0x87654321);

        IEnumerableIntegrations.Wire[] memory wires2 = new IEnumerableIntegrations.Wire[](2);
        wires2[0] = IEnumerableIntegrations.Wire(0x89ABCDEF, 0xFECDAB98);
        wires2[1] = IEnumerableIntegrations.Wire(0x11111111, 0x33333333);

        beacon.__addIntegrationId(integrationId1);
        beacon.__addIntegrationId(integrationId2);

        beacon.__setConfig(integrationId1, IEnumerableIntegrations.Config(facet1, wires1));
        beacon.__setConfig(integrationId2, IEnumerableIntegrations.Config(facet2, wires2));

        IEnumerableIntegrations.Integration[] memory integrations = beacon.integrations();

        assertEq(integrations.length, 2);

        assertEq(integrations[0].id,                  integrationId1);
        assertEq(integrations[0].config.facet,        facet1);
        assertEq(integrations[0].config.wires.length, wires1.length);

        assertEq(integrations[0].config.wires[0].callSelector,     wires1[0].callSelector);
        assertEq(integrations[0].config.wires[0].delegateSelector, wires1[0].delegateSelector);

        assertEq(integrations[1].id,                  integrationId2);
        assertEq(integrations[1].config.facet,        facet2);
        assertEq(integrations[1].config.wires.length, wires2.length);

        assertEq(integrations[1].config.wires[0].callSelector,     wires2[0].callSelector);
        assertEq(integrations[1].config.wires[0].delegateSelector, wires2[0].delegateSelector);

        assertEq(integrations[1].config.wires[1].callSelector,     wires2[1].callSelector);
        assertEq(integrations[1].config.wires[1].delegateSelector, wires2[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** getConfig Tests                                                                        ***/
    /**********************************************************************************************/

    function test_getConfig() external {
        bytes32 integrationId = "SOME_INTEGRATION";

        IEnumerableIntegrations.Config memory config = beacon.getConfig(integrationId);

        assertEq(config.facet,        address(0));
        assertEq(config.wires.length, 0);

        address facet = makeAddr("facet");

        bytes4[] memory callSelectors = new bytes4[](3);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;

        bytes4[] memory delegateSelectors = new bytes4[](3);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);
        wires[0] = IEnumerableIntegrations.Wire(callSelectors[0], delegateSelectors[0]);
        wires[1] = IEnumerableIntegrations.Wire(callSelectors[1], delegateSelectors[1]);
        wires[2] = IEnumerableIntegrations.Wire(callSelectors[2], delegateSelectors[2]);

        beacon.__setConfig(integrationId, IEnumerableIntegrations.Config(facet, wires));

        config = beacon.getConfig(integrationId);

        assertEq(config.facet,        facet);
        assertEq(config.wires.length, wires.length);

        assertEq(config.wires[0].callSelector,     callSelectors[0]);
        assertEq(config.wires[0].delegateSelector, delegateSelectors[0]);

        assertEq(config.wires[1].callSelector,     callSelectors[1]);
        assertEq(config.wires[1].delegateSelector, delegateSelectors[1]);

        assertEq(config.wires[2].callSelector,     callSelectors[2]);
        assertEq(config.wires[2].delegateSelector, delegateSelectors[2]);
    }

    /**********************************************************************************************/
    /*** getConfigs Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getConfigs() external {
        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = "INTEGRATION_1";
        integrationIds[1] = "INTEGRATION_2";

        IEnumerableIntegrations.Config[] memory configs = beacon.getConfigs(integrationIds);

        assertEq(configs.length, integrationIds.length);

        assertEq(configs[0].facet,        address(0));
        assertEq(configs[0].wires.length, 0);
        assertEq(configs[1].facet,        address(0));
        assertEq(configs[1].wires.length, 0);

        address facet1 = makeAddr("facet1");
        address facet2 = makeAddr("facet2");

        IEnumerableIntegrations.Wire[] memory wires1 = new IEnumerableIntegrations.Wire[](1);
        wires1[0] = IEnumerableIntegrations.Wire(0x12345678, 0x87654321);

        IEnumerableIntegrations.Wire[] memory wires2 = new IEnumerableIntegrations.Wire[](2);
        wires2[0] = IEnumerableIntegrations.Wire(0x89ABCDEF, 0xFECDAB98);
        wires2[1] = IEnumerableIntegrations.Wire(0x11111111, 0x33333333);

        beacon.__setConfig(integrationIds[0], IEnumerableIntegrations.Config(facet1, wires1));
        beacon.__setConfig(integrationIds[1], IEnumerableIntegrations.Config(facet2, wires2));

        configs = beacon.getConfigs(integrationIds);

        assertEq(configs.length, integrationIds.length);

        assertEq(configs[0].facet,        facet1);
        assertEq(configs[0].wires.length, wires1.length);

        assertEq(configs[0].wires[0].callSelector,     wires1[0].callSelector);
        assertEq(configs[0].wires[0].delegateSelector, wires1[0].delegateSelector);

        assertEq(configs[1].facet,        facet2);
        assertEq(configs[1].wires.length, wires2.length);

        assertEq(configs[1].wires[0].callSelector,     wires2[0].callSelector);
        assertEq(configs[1].wires[0].delegateSelector, wires2[0].delegateSelector);

        assertEq(configs[1].wires[1].callSelector,     wires2[1].callSelector);
        assertEq(configs[1].wires[1].delegateSelector, wires2[1].delegateSelector);
    }

    /**********************************************************************************************/
    /*** getDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_getDispatch() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        beacon.__setDispatch(callSelector, IEnumerableIntegrations.Dispatch(facet, delegateSelector));

        IEnumerableIntegrations.Dispatch memory returnedDispatch = beacon.getDispatch(callSelector);

        assertEq(returnedDispatch.facet,            facet);
        assertEq(returnedDispatch.delegateSelector, delegateSelector);
    }

    /**********************************************************************************************/
    /*** getDispatches Tests                                                                    ***/
    /**********************************************************************************************/

    function test_getDispatches() external {
        address[] memory facets = new address[](2);
        facets[0] = makeAddr("facet1");
        facets[1] = makeAddr("facet2");

        bytes4[] memory callSelectors = new bytes4[](3);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;

        bytes4[] memory delegateSelectors = new bytes4[](3);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;

        beacon.__setDispatch(callSelectors[0], IEnumerableIntegrations.Dispatch(facets[0], delegateSelectors[0]));
        beacon.__setDispatch(callSelectors[1], IEnumerableIntegrations.Dispatch(facets[1], delegateSelectors[1]));
        beacon.__setDispatch(callSelectors[2], IEnumerableIntegrations.Dispatch(facets[1], delegateSelectors[2]));

        IEnumerableIntegrations.Dispatch[] memory dispatches = beacon.getDispatches(callSelectors);

        assertEq(dispatches.length, 3);

        assertEq(dispatches[0].facet,            facets[0]);
        assertEq(dispatches[0].delegateSelector, delegateSelectors[0]);
        assertEq(dispatches[1].facet,            facets[1]);
        assertEq(dispatches[1].delegateSelector, delegateSelectors[1]);
        assertEq(dispatches[2].facet,            facets[1]);
        assertEq(dispatches[2].delegateSelector, delegateSelectors[2]);
    }

    /**********************************************************************************************/
    /*** supportsInterface Tests                                                                ***/
    /**********************************************************************************************/

    function test_supportsInterface() external view {
        assertEq(beacon.supportsInterface(type(IBeacon).interfaceId),                  true);
        assertEq(beacon.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(beacon.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(beacon.supportsInterface(type(IERC165).interfaceId),                  true);
        assertEq(beacon.supportsInterface(0x00000000),                                 false);
        assertEq(beacon.supportsInterface(0xffffffff),                                 false);
    }

}
