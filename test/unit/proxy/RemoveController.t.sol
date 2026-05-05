// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract Freezable_RemoveAllocator_TestBase is UnitTestBase {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    event AllocatorRemoved(address indexed allocator);

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

        vm.startPrank(admin);
        almProxyFreezable.grantRole(FREEZER_ROLE,   freezer);
        almProxyFreezable.grantRole(ALLOCATOR_ROLE, allocator);
        vm.stopPrank();

        target = address(new MockTarget());
    }

}

contract ALMProxy_Freezable_RemoveAllocator_FailureTests is Freezable_RemoveAllocator_TestBase {

    function test_removeAllocator_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER_ROLE
        ));
        almProxyFreezable.removeAllocator(allocator);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER_ROLE
        ));
        almProxyFreezable.removeAllocator(allocator);
    }

    function test_removeAllocator_notLiveAllocator() public {
        vm.prank(freezer);
        vm.expectRevert("ALMProxyFreezable/not-live-allocator");
        almProxyFreezable.removeAllocator(exampleAddress);
    }

}

contract ALMProxy_Freezable_RemoveAllocator_SuccessTests is Freezable_RemoveAllocator_TestBase {

    function test_removeAllocator() public {
        // ALM Proxy Freezable is msg.sender, target emits the event
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

        // Before has allocator role
        assertTrue(almProxyFreezable.hasRole(ALLOCATOR_ROLE, allocator));

        // Freezer comes in and removes allocator.
        vm.prank(freezer);
        vm.expectEmit(address(almProxyFreezable));
        emit AllocatorRemoved(allocator);
        almProxyFreezable.removeAllocator(allocator);

        // After no longer has allocator role
        assertFalse(almProxyFreezable.hasRole(ALLOCATOR_ROLE, allocator));

        // After can no longer call as allocator
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            allocator,
            ALLOCATOR_ROLE
        ));
        almProxyFreezable.doCall(target, data);
    }

}
