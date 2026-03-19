// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { IParameterKeysErrors } from "../../../src/interfaces/IParameterKeysErrors.sol";

import {
    getParameterKey,
    combineKeyComponents,
    addressToKeyComponent,
    bytes4ToKeyComponent,
    bytes32ToKeyComponent,
    int256ToKeyComponent,
    uint256ToKeyComponent
} from "../../../src/ParameterKeys.sol";

contract ParameterKeysHarness {

    function getParameterKey(string[] memory keyComponents) external pure returns (string memory) {
        return getParameterKey(keyComponents);
    }

    function combineKeyComponents(string memory left, string memory right)
        external
        pure
        returns (string memory)
    {
        return combineKeyComponents(left, right);
    }

    function addressToKeyComponent(address account) external pure returns (string memory) {
        return addressToKeyComponent(account);
    }

    function bytes4ToKeyComponent(bytes4 value) external pure returns (string memory) {
        return bytes4ToKeyComponent(value);
    }

    function bytes32ToKeyComponent(bytes32 value) external pure returns (string memory) {
        return bytes32ToKeyComponent(value);
    }

    function int256ToKeyComponent(int256 value) external pure returns (string memory) {
        return int256ToKeyComponent(value);
    }

    function uint256ToKeyComponent(uint256 value) external pure returns (string memory) {
        return uint256ToKeyComponent(value);
    }

}

contract ParameterKeys_Tests is Test {

    ParameterKeysHarness internal harness;

    function setUp() external {
        harness = new ParameterKeysHarness();
    }

    function test_getParameterKey_noKeyComponents() external {
        vm.expectRevert(IParameterKeysErrors.NoKeyComponents.selector);
        harness.getParameterKey(new string[](0));
    }

    function test_getParameterKey_emptyKeyComponent() external {
        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.getParameterKey(new string[](1));

        string[] memory keyComponents = new string[](3);
        keyComponents[0] = "";
        keyComponents[1] = "pau";
        keyComponents[2] = "test";

        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.getParameterKey(keyComponents);

        keyComponents[0] = "sky";
        keyComponents[1] = "";
        keyComponents[2] = "test";

        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.getParameterKey(keyComponents);

        keyComponents[0] = "sky";
        keyComponents[1] = "pau";
        keyComponents[2] = "";

        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.getParameterKey(keyComponents);
    }

    function test_getParameterKey() external view {
        string[] memory keyComponents;

        keyComponents = new string[](1);
        keyComponents[0] = "sky";
        assertEq(harness.getParameterKey(keyComponents), "sky");

        keyComponents = new string[](2);
        keyComponents[0] = "sky";
        keyComponents[1] = "pau";
        assertEq(harness.getParameterKey(keyComponents), "sky.pau");

        keyComponents = new string[](3);
        keyComponents[0] = "sky";
        keyComponents[1] = "pau";
        keyComponents[2] = "foo";
        assertEq(harness.getParameterKey(keyComponents), "sky.pau.foo");
    }

    function test_combineKeyComponents_emptyKeyComponent() external {
        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.combineKeyComponents("sky", "");

        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.combineKeyComponents("", "pau");

        vm.expectRevert(IParameterKeysErrors.EmptyKeyComponent.selector);
        harness.combineKeyComponents("", "");
    }

    function test_combineKeyComponents() external view {
        assertEq(harness.combineKeyComponents("sky", "pau"),     "sky.pau");
        assertEq(harness.combineKeyComponents("sky.pau", "foo"), "sky.pau.foo");
        assertEq(harness.combineKeyComponents("sky", "pau.foo"), "sky.pau.foo");
    }

    function test_addressToKeyComponent() external view {
        assertEq(
            harness.addressToKeyComponent(0x123456789aBCdef0123456789AbCDEF012345678),
            "0x123456789abcdef0123456789abcdef012345678"
        );
        assertEq(
            harness.addressToKeyComponent(0x0000000000000000000000000000000000000000),
            "0x0000000000000000000000000000000000000000"
        );
    }

    function test_bytes4ToKeyComponent() external view {
        assertEq(harness.bytes4ToKeyComponent(0x12345678), "0x12345678");
        assertEq(harness.bytes4ToKeyComponent(0x00345678), "0x00345678");
        assertEq(harness.bytes4ToKeyComponent(0x00005678), "0x00005678");
        assertEq(harness.bytes4ToKeyComponent(0x00000078), "0x00000078");
        assertEq(harness.bytes4ToKeyComponent(0x00000000), "0x00000000");
    }

    function test_bytes32ToKeyComponent() external view {
        assertEq(
            harness.bytes32ToKeyComponent(0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0),
            "0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0"
        );
        assertEq(
            harness.bytes32ToKeyComponent(0x0000000000000000123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0),
            "0x0000000000000000123456789abcdef0123456789abcdef0123456789abcdef0"
        );
        assertEq(
            harness.bytes32ToKeyComponent(0x0000000000000000000000000000000000000000000000000000000000000000),
            "0x0000000000000000000000000000000000000000000000000000000000000000"
        );
    }

    function test_int256ToKeyComponent() external view {
        assertEq(
            harness.int256ToKeyComponent(type(int256).min),
            "-57896044618658097711785492504343953926634992332820282019728792003956564819968"
        );
        assertEq(
            harness.int256ToKeyComponent(-1234567890123456789012345678901234567890),
            "-1234567890123456789012345678901234567890"
        );
        assertEq(
            harness.int256ToKeyComponent(0),
            "0"
        );
        assertEq(
            harness.int256ToKeyComponent(1234567890123456789012345678901234567890),
            "1234567890123456789012345678901234567890"
        );
        assertEq(
            harness.int256ToKeyComponent(type(int256).max),
            "57896044618658097711785492504343953926634992332820282019728792003956564819967"
        );
    }

    function test_uint256ToKeyComponent() external view {
        assertEq(
            harness.uint256ToKeyComponent(0),
            "0"
        );
        assertEq(
            harness.uint256ToKeyComponent(1234567890123456789012345678901234567890),
            "1234567890123456789012345678901234567890"
        );
        assertEq(
            harness.uint256ToKeyComponent(type(uint256).max),
            "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        );
    }

}
