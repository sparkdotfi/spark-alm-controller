// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library RateLimitHelpers {

    function makeAddressKey(bytes32 key, address asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, asset));
    }

    function makeAddressAddressKey(bytes32 key, address asset, address destination) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, asset, destination));
    }

    function makeUint32Key(bytes32 key, uint32 domain) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, domain));
    }

}
