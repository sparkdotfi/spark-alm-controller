// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import "../UnitTestBase.t.sol";

contract ALMProxyFreezableRemoveControllerTestBase is UnitTestBase {

    event ControllerRemoved(address indexed relayer);

    ALMProxyFreezable almProxyFreezable;

    address controller = makeAddr("controller");

    function setUp() public virtual {
        almProxyFreezable = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxyFreezable.grantRole(FREEZER, freezer);
        almProxyFreezable.grantRole(CONTROLLER, controller);
        vm.stopPrank();
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
        // Before can call as controller
        vm.prank(controller);
        // We need to call a contract here. Calling a view function will still demonstrate the role check.
        almProxyFreezable.doCall(
            address(almProxyFreezable),
            abi.encodeCall(AccessControl.hasRole, (FREEZER, address(1)))
        );

        // Before has controller role
        assertTrue(almProxyFreezable.hasRole(CONTROLLER, controller));

        // Freezer comes in and removes controller.
        vm.prank(freezer);
        vm.expectEmit();
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
        almProxyFreezable.doCall(
            address(almProxyFreezable),
            abi.encodeCall(AccessControl.hasRole, (FREEZER, address(1)))
        );
    }

}
