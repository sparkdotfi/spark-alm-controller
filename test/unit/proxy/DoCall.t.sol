// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget, MockRevertingTarget, MockStorageWriter } from "../mocks/MockTarget.sol";

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
        almProxy.grantRole(CONTROLLER_ROLE, controller);

        target = address(new MockTarget());
    }

}

contract ALMProxy_DoCall_FailureTests is ALMProxy_Call_TestBase {

    function test_doCall_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            CONTROLLER_ROLE
        ));
        almProxy.doCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        almProxy.doCall(target, data);
    }

}

contract ALMProxy_DoCall_SuccessTests is ALMProxy_Call_TestBase {

    function test_doCall() public {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 0
        });
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
            CONTROLLER_ROLE
        ));
        almProxy.doCallWithValue(target, data, 1e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
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
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 1e18
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() public {
        vm.deal(controller, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxy),
            value          : 1e18
        });
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
            CONTROLLER_ROLE
        ));
        almProxy.doDelegateCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            CONTROLLER_ROLE
        ));
        almProxy.doDelegateCall(target, data);
    }

}

contract ALMProxy_DoDelegateCall_SuccessTests is ALMProxy_Call_TestBase {

    function test_doDelegateCall() public {
        // L1 Controller is msg.sender, almProxy emits the event
        vm.expectEmit(address(almProxy));
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : controller,
            value          : 0
        });
        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

abstract contract ALMProxyFreezable_Call_TestBase is UnitTestBase {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    ALMProxyFreezable almProxyFreezable;

    address target;

    address exampleAddress = makeAddr("exampleAddress");

    bytes data = abi.encodeWithSignature(
        "exampleCall(address,uint256)",
        exampleAddress,
        42
    );

    function setUp() public virtual {
        almProxyFreezable = new ALMProxyFreezable(admin);

        vm.prank(admin);
        almProxyFreezable.grantRole(ALLOCATOR_ROLE, allocator);

        target = address(new MockTarget());
    }

}

contract ALMProxyFreezable_DoCall_FailureTests is ALMProxyFreezable_Call_TestBase {

    function test_doCall_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);
    }

}

contract ALMProxyFreezable_DoCall_SuccessTests is ALMProxyFreezable_Call_TestBase {

    function test_doCall() public {
        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 0
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxyFreezable_DoCallWithValue_FailureTests is ALMProxyFreezable_Call_TestBase {

    function test_doCallWithValue_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);
    }

    function test_doCallWithValue_notEnoughBalanceBoundary() public {
        vm.deal(address(almProxyFreezable), 1e18 - 1);

        vm.startPrank(allocator);

        vm.expectRevert(abi.encodeWithSignature(
            "AddressInsufficientBalance(address)",
            address(almProxyFreezable)
        ));
        almProxyFreezable.doCallWithValue(target, data, 1e18);

        vm.deal(address(almProxyFreezable), 1e18);

        almProxyFreezable.doCallWithValue(target, data, 1e18);
    }

}

contract ALMProxyFreezable_DoCallWithValue_SuccessTests is ALMProxyFreezable_Call_TestBase {

    function test_doCallWithValue() public {
        vm.deal(address(almProxyFreezable), 1e18);

        // ALM Proxy is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 1e18
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCallWithValue(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

    function test_doCallWithValue_msgValue() public {
        vm.deal(allocator, 1e18);

        // ALM Proxy is msg.sender, target emits the event, msg.value sent to proxy then target
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 1e18
        });
        vm.prank(allocator);
        bytes memory returnData = almProxyFreezable.doCallWithValue{value: 1e18}(target, data, 1e18);

        assertEq(abi.decode(returnData, (uint256)), 84);
    }

}

contract ALMProxy_DoCall_RevertPropagationTests is ALMProxy_Call_TestBase {

    function test_doCall_revertsWithReason() public {
        address revertingTarget = address(new MockRevertingTarget());

        vm.expectRevert("MockRevertingTarget/reverted");
        vm.prank(controller);
        almProxy.doCall(revertingTarget, abi.encodeWithSignature("revertWithReason()"));
    }

    function test_doCall_revertsWithCustomError() public {
        address revertingTarget = address(new MockRevertingTarget());

        vm.expectRevert(MockRevertingTarget.MockError.selector);
        vm.prank(controller);
        almProxy.doCall(revertingTarget, abi.encodeWithSignature("revertWithCustomError()"));
    }

}

contract ALMProxy_TargetEmptyCodeTests is ALMProxy_Call_TestBase {

    function test_doCall_targetEmptyCode() public {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doCall(emptyTarget, "");
    }

    function test_doCallWithValue_targetEmptyCode() public {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doCallWithValue(emptyTarget, "", 0);
    }

    function test_doDelegateCall_targetEmptyCode() public {
        address emptyTarget = makeAddr("emptyTarget");

        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", emptyTarget));
        vm.prank(controller);
        almProxy.doDelegateCall(emptyTarget, "");
    }

}

contract ALMProxy_DoDelegateCall_StorageEffectTests is ALMProxy_Call_TestBase {

    function test_doDelegateCall_writesToProxyStorage() public {
        address writer = address(new MockStorageWriter());

        uint256 slot  = 1000;
        uint256 value = 42;

        vm.prank(controller);
        bytes memory returnData = almProxy.doDelegateCall(writer, abi.encodeWithSignature("write(uint256,uint256)", slot, value));

        address context = abi.decode(returnData, (address));

        // delegatecall executes in the proxy's storage context: the slot is written in the proxy,
        // and the target contract's own storage is untouched.
        assertEq(uint256(vm.load(address(almProxy), bytes32(slot))), value);
        assertEq(uint256(vm.load(writer,            bytes32(slot))), 0);
        assertEq(context,                           address(almProxy));
    }

}

contract ALMProxyFreezable_DoCall_RevertPropagationTests is ALMProxyFreezable_Call_TestBase {

    function test_doCall_revertsWithReason() public {
        address revertingTarget = address(new MockRevertingTarget());

        vm.prank(allocator);
        vm.expectRevert("MockRevertingTarget/reverted");
        almProxyFreezable.doCall(revertingTarget, abi.encodeWithSignature("revertWithReason()"));
    }

    function test_doCallWithValue_revertsWithReason() public {
        address revertingTarget = address(new MockRevertingTarget());

        vm.deal(address(almProxyFreezable), 1e18);

        vm.prank(allocator);
        vm.expectRevert("MockRevertingTarget/reverted");
        almProxyFreezable.doCallWithValue(revertingTarget, abi.encodeWithSignature("revertWithReason()"), 1e18);
    }

}
