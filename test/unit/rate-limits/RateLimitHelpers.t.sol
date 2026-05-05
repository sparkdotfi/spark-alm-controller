// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { RateLimits, IRateLimits } from "../../../src/RateLimits.sol";

import {
    makeAddressAddressAddressKey as makeAddressAddressAddressKeyImplementation,
    makeAddressAddressUint32Key as makeAddressAddressUint32KeyImplementation,
    makeAddressAddressKey as makeAddressAddressKeyImplementation,
    makeAddressBytes32Key as makeAddressBytes32KeyImplementation,
    makeAddressKey as makeAddressKeyImplementation,
    makeAddressUint16AddressKey as makeAddressUint16AddressKeyImplementation,
    makeAddressUint16Key as makeAddressUint16KeyImplementation,
    makeBytes32Key as makeBytes32KeyImplementation,
    makeUint32Key as makeUint32KeyImplementation
} from "../../../src/libraries/RateLimitHelpers.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract RateLimitHelpersHarness {

    function makeAddressKey(bytes32 key, address asset) public pure returns (bytes32) {
        return makeAddressKeyImplementation(key, asset);
    }

    function makeAddressAddressKey(bytes32 key, address asset, address destination) public pure returns (bytes32) {
        return makeAddressAddressKeyImplementation(key, asset, destination);
    }

    function makeAddressAddressAddressKey(bytes32 key, address asset, address destination, address module) public pure returns (bytes32) {
        return makeAddressAddressAddressKeyImplementation(key, asset, destination, module);
    }

    function makeAddressBytes32Key(bytes32 key, address asset, bytes32 poolId) public pure returns (bytes32) {
        return makeAddressBytes32KeyImplementation(key, asset, poolId);
    }

    function makeAddressUint16Key(bytes32 key, address asset, uint16 domain) public pure returns (bytes32) {
        return makeAddressUint16KeyImplementation(key, asset, domain);
    }

    function makeAddressUint16AddressKey(bytes32 key, address asset, uint16 domain, address module) public pure returns (bytes32) {
        return makeAddressUint16AddressKeyImplementation(key, asset, domain, module);
    }

    function makeAddressAddressUint32Key(bytes32 key, address asset, address destination, uint32 domain) public pure returns (bytes32) {
        return makeAddressAddressUint32KeyImplementation(key, asset, destination, domain);
    }

    function makeBytes32Key(bytes32 key, bytes32 asset) public pure returns (bytes32) {
        return makeBytes32KeyImplementation(key, asset);
    }

    function makeUint32Key(bytes32 key, uint32 domain) public pure returns (bytes32) {
        return makeUint32KeyImplementation(key, domain);
    }

}

contract RateLimitHelpers_Tests is UnitTestBase {

    bytes32 internal constant KEY  = "KEY";
    string  internal constant NAME = "NAME";

    address internal controller = makeAddr("controller");

    RateLimits              internal rateLimits;
    RateLimitHelpersHarness internal wrapper;

    function setUp() public {
        // Set wrapper as admin so it can set rate limits
        wrapper    = new RateLimitHelpersHarness();
        rateLimits = new RateLimits(address(wrapper));
    }

    function _assertLimitData(
        bytes32 key,
        uint256 maxAmount,
        uint256 slope,
        uint256 lastAmount,
        uint256 lastUpdated
    )
        internal view
    {
        IRateLimits.RateLimitData memory d = rateLimits.getRateLimitData(key);

        assertEq(d.maxAmount,   maxAmount);
        assertEq(d.slope,       slope);
        assertEq(d.lastAmount,  lastAmount);
        assertEq(d.lastUpdated, lastUpdated);
    }

    function test_makeAddressKey() external {
        assertEq(
            wrapper.makeAddressKey(KEY, makeAddr("account")),
            keccak256(abi.encode(KEY, makeAddr("account")))
        );
    }

    function test_makeAddressAddressKey() external {
        assertEq(
            wrapper.makeAddressAddressKey(KEY, makeAddr("account"), makeAddr("otherAccount")),
            keccak256(abi.encode(KEY, makeAddr("account"), makeAddr("otherAccount")))
        );
    }

    function test_makeAddressAddressAddressKey() external {
        assertEq(
            wrapper.makeAddressAddressAddressKey(KEY, makeAddr("account"), makeAddr("destination"), makeAddr("module")),
            keccak256(abi.encode(KEY, makeAddr("account"), makeAddr("destination"), makeAddr("module")))
        );
    }

    function test_makeAddressBytes32Key() external {
        assertEq(
            wrapper.makeAddressBytes32Key(KEY, makeAddr("account"), bytes32(type(uint256).max)),
            keccak256(abi.encode(KEY, makeAddr("account"), bytes32(type(uint256).max)))
        );
    }

    function test_makeAddressUint16Key() external {
        assertEq(
            wrapper.makeAddressUint16Key(KEY, makeAddr("account"), type(uint16).max),
            keccak256(abi.encode(KEY, makeAddr("account"), uint16(type(uint16).max)))
        );
    }

    function test_makeAddressUint16AddressKey() external {
        assertEq(
            wrapper.makeAddressUint16AddressKey(KEY, makeAddr("account"), type(uint16).max, makeAddr("module")),
            keccak256(abi.encode(KEY, makeAddr("account"), uint16(type(uint16).max), makeAddr("module")))
        );
    }

    function test_makeAddressAddressUint32Key() external {
        assertEq(
            wrapper.makeAddressAddressUint32Key(KEY, makeAddr("account"), makeAddr("destination"), type(uint32).max),
            keccak256(abi.encode(KEY, makeAddr("account"), makeAddr("destination"), uint32(type(uint32).max)))
        );
    }

    function test_makeBytes32Key() external view {
        assertEq(
            wrapper.makeBytes32Key(KEY, bytes32(type(uint256).max)),
            keccak256(abi.encode(KEY, bytes32(type(uint256).max)))
        );
    }

    function test_makeUint32Key() external view {
        assertEq(
            wrapper.makeUint32Key(KEY, type(uint32).max),
            keccak256(abi.encode(KEY, type(uint32).max))
        );
    }

}
