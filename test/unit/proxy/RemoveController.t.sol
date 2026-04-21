// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { MockTarget } from "../mocks/MockTarget.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract Freezable_RemoveRelayer_TestBase is UnitTestBase {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    event RelayerRemoved(address indexed relayer);

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
        almProxyFreezable.grantRole(FREEZER_ROLE, freezer);
        almProxyFreezable.grantRole(RELAYER_ROLE, relayer);
        vm.stopPrank();

        target = address(new MockTarget());
    }

}

contract ALMProxy_Freezable_RemoveRelayer_FailureTests is Freezable_RemoveRelayer_TestBase {

    function test_removeRelayer_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER_ROLE
        ));
        almProxyFreezable.removeRelayer(relayer);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER_ROLE
        ));
        almProxyFreezable.removeRelayer(relayer);
    }

    function test_removeRelayer_notLiveRelayer() public {
        vm.prank(freezer);
        vm.expectRevert("ALMProxyFreezable/not-live-relayer");
        almProxyFreezable.removeRelayer(exampleAddress);
    }

}

contract ALMProxy_Freezable_RemoveRelayer_SuccessTests is Freezable_RemoveRelayer_TestBase {

    function test_removeRelayer() public {
        // ALM Proxy Freezable is msg.sender, target emits the event
        vm.expectEmit(target);
        emit ExampleEvent({
            exampleAddress : exampleAddress,
            exampleValue   : 42,
            exampleReturn  : 84,
            caller         : address(almProxyFreezable),
            value          : 0
        });
        vm.prank(relayer);
        bytes memory returnData = almProxyFreezable.doCall(target, data);

        assertEq(abi.decode(returnData, (uint256)), 84);

        // Before has relayer role
        assertTrue(almProxyFreezable.hasRole(RELAYER_ROLE, relayer));

        // Freezer comes in and removes relayer.
        vm.prank(freezer);
        vm.expectEmit(address(almProxyFreezable));
        emit RelayerRemoved(relayer);
        almProxyFreezable.removeRelayer(relayer);

        // After no longer has relayer role
        assertFalse(almProxyFreezable.hasRole(RELAYER_ROLE, relayer));

        // After can no longer call as relayer
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER_ROLE
        ));
        almProxyFreezable.doCall(target, data);
    }

}
