// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IBeacon }                 from "../../src/interfaces/IBeacon.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";

import { Beacon } from "../../src/Beacon.sol";

import { Integration_TestBase } from "./TestBase.t.sol";

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

contract Beacon_IntegrationTests is Integration_TestBase {

    function setUp() external {
        _deploy();
    }

    /**********************************************************************************************/
    /*** setIntegration Tests                                                                   ***/
    /**********************************************************************************************/

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
        beacon.setIntegration(bytes32(0), config);
    }

    /**********************************************************************************************/
    /*** removeIntegration Tests                                                                ***/
    /**********************************************************************************************/

    function test_removeIntegration_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        beacon.removeIntegration(bytes32(0));
    }

    /**********************************************************************************************/
    /*** Story Tests                                                                            ***/
    /**********************************************************************************************/

    function test_setIntegration_removeIntegration() external {
        bytes32 integrationId = "SOME_INTEGRATION";

        address facet = address(new MockFacet1());

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

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.expectEmit(address(beacon));
        emit IEnumerableIntegrations.IntegrationSet(integrationId, config);

        vm.prank(beaconAdmin);
        beacon.setIntegration(integrationId, config);

        IEnumerableIntegrations.Config memory returnedConfig = beacon.getConfig(integrationId);

        assertEq(returnedConfig.facet,        facet);
        assertEq(returnedConfig.wires.length, wires.length);

        assertEq(returnedConfig.wires[0].callSelector,     wires[0].callSelector);
        assertEq(returnedConfig.wires[0].delegateSelector, wires[0].delegateSelector);

        assertEq(returnedConfig.wires[1].callSelector,     wires[1].callSelector);
        assertEq(returnedConfig.wires[1].delegateSelector, wires[1].delegateSelector);

        assertEq(returnedConfig.wires[2].callSelector,     wires[2].callSelector);
        assertEq(returnedConfig.wires[2].delegateSelector, wires[2].delegateSelector);

        vm.expectEmit(address(beacon));
        emit IEnumerableIntegrations.IntegrationRemoved(integrationId);

        vm.prank(beaconAdmin);
        beacon.removeIntegration(integrationId);

        returnedConfig = beacon.getConfig(integrationId);

        assertEq(returnedConfig.facet,        address(0));
        assertEq(returnedConfig.wires.length, 0);
    }

}
