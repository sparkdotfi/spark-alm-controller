// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import "../UnitTestBase.t.sol";

contract ALMProxyFreezableRemoveControllerTestBase is UnitTestBase {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    event ControllerRemoved(address indexed relayer);

    ALMProxyFreezable almProxyFreezable;

    address target;

    address controller     = makeAddr("controller");
    address exampleAddress = makeAddr("exampleAddress");

    bytes data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxyFreezable = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxyFreezable.grantRole(FREEZER,    freezer);
        almProxyFreezable.grantRole(CONTROLLER, controller);
        vm.stopPrank();

        target = address(new MockTarget());
    }

}

contract ALMProxyFreezableRemoveControllerFailureTests is ALMProxyFreezableRemoveControllerTestBase {

    function test_removeController_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        almProxyFreezable.removeController(controller);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        almProxyFreezable.removeController(controller);
    }

}

contract ALMProxyFreezableRemoveControllerSuccessTests is ALMProxyFreezableRemoveControllerTestBase {

    function test_removeController() public {
        // ALM Proxy Freezable is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent(exampleAddress, 42, 84, address(almProxyFreezable), 0);
        vm.prank(controller);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);

        // Before has controller role
        assertTrue(almProxyFreezable.hasRole(CONTROLLER, controller));

        // Freezer comes in and removes controller.
        vm.prank(freezer);
        vm.expectEmit(address(almProxyFreezable));
        emit ControllerRemoved(controller);
        almProxyFreezable.removeController(controller);

        // After no longer has controller role
        assertFalse(almProxyFreezable.hasRole(CONTROLLER, controller));

        // After can no longer call as controller
        vm.prank(controller);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            controller,
            CONTROLLER
        ));
        almProxyFreezable.doCall(target, data);
    }

}
