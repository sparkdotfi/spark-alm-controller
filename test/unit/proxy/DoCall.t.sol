// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract ALMProxy_Call_TestBase is UnitTestBase {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    ALMProxy almProxy;

    address target;

    address controller     = makeAddr("controller");
    address exampleAddress = makeAddr("exampleAddress");

    bytes data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxy = new ALMProxy(admin);

        vm.prank(admin);
        almProxy.grantRole(CONTROLLER, controller);

        target = address(new MockTarget());
    }

}

contract ALMProxy_DoCall_FailureTests is ALMProxy_Call_TestBase {

    function test_doCall_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER
        ));
        almProxy.doCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER
        ));
        almProxy.doCall(target, data);
    }

}

contract ALMProxy_DoCall_SuccessTests is ALMProxy_Call_TestBase {

    function test_doCall() public {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent(exampleAddress, 42, 84, address(almProxy), 0);
        vm.prank(controller);
        bytes memory returnData = almProxy.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_DoCallWithValue_FailureTests is ALMProxy_Call_TestBase {

    function test_doCallWithValue_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER
        ));
        almProxy.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_notEnoughBalanceBoundary() public {
        vm.deal(address(almProxy), 1e18 - 1);

        vm.startPrank(controller);

        vm.expectRevert(abi.encodeWithSignature(
            "AddressInsufficientBalance(address)",
            address(almProxy)
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.deal(address(almProxy), 1e18);

        almProxy.doCallWithValue(target, data, 1e18);
    }

}

contract ALMProxy_DoCallWithValue_SuccessTests is ALMProxy_Call_TestBase {

    function test_doCallWithValue() public {
        vm.deal(address(almProxy), 1e18);

        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent(exampleAddress, 42, 84, address(almProxy), 1e18);
        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() public {
        vm.deal(controller, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit ExampleEvent(exampleAddress, 42, 84, address(almProxy), 1e18);
        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue{value: 1e18}(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_DoDelegateCall_FailureTests is ALMProxy_Call_TestBase {

    function test_doDelegateCall_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER
        ));
        almProxy.doDelegateCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER
        ));
        almProxy.doDelegateCall(target, data);
    }

}

contract ALMProxy_DoDelegateCall_SuccessTests is ALMProxy_Call_TestBase {

    function test_doDelegateCall() public {
        // L1 Controller is msg.sender, almProxy emits the event
        vm.expectEmit(address(almProxy));
        emit ExampleEvent(exampleAddress, 42, 84, controller, 0);
        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_Freezable_Tests is
    ALMProxy_DoCall_FailureTests,
    ALMProxy_DoCall_SuccessTests,
    ALMProxy_DoCallWithValue_FailureTests,
    ALMProxy_DoCallWithValue_SuccessTests,
    ALMProxy_DoDelegateCall_FailureTests,
    ALMProxy_DoDelegateCall_SuccessTests
{

    function setUp() public override {
        super.setUp();

        // Overwrite almProxy with ALMProxyFreezable to demonstrate equivalent functionality
        almProxy = new ALMProxyFreezable(admin);

        vm.startPrank(admin);
        almProxy.grantRole(FREEZER,    freezer);
        almProxy.grantRole(CONTROLLER, controller);
        vm.stopPrank();
    }

}
