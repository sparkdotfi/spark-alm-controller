// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

function makeAddressKey(bytes32 key, address a) pure returns (bytes32) {
    return keccak256(abi.encode(key, a));
}

function makeUint32Key(bytes32 key, uint32 a) pure returns (bytes32) {
    return keccak256(abi.encode(key, a));
}

library RateLimitHelpers {

    function makeAddressKey(bytes32 key, address a) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, a));
    }

    function makeAddressAddressKey(bytes32 key, address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, a, b));
    }

    function makeBytes32Key(bytes32 key, bytes32 a) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, a));
    }

    function makeUint32Key(bytes32 key, uint32 a) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, a));
    }

}
