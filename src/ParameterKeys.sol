// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Strings } from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import { IParameterKeysErrors } from "./interfaces/IParameterKeysErrors.sol";

/**
* @notice Combines an array of key components into a single key, using the delimiter.
* @param  keyComponents The key components to combine.
* @return key           The combined key.
*/
function getParameterKey(string[] memory keyComponents) pure returns (string memory key) {
    require(keyComponents.length > 0,           IParameterKeysErrors.NoKeyComponents());
    require(bytes(keyComponents[0]).length > 0, IParameterKeysErrors.EmptyKeyComponent());

    for (uint256 i; i < keyComponents.length; ++i) {
        key = i == 0 ? keyComponents[i] : combineKeyComponents(key, keyComponents[i]);
    }
}

function combineKeyComponents(string memory left, string memory right)
    pure
    returns (string memory key)
{
    require(
        bytes(left).length > 0 && bytes(right).length > 0,
        IParameterKeysErrors.EmptyKeyComponent()
    );

    return string.concat(left, ".", right);
}

function addressToKeyComponent(address account) pure returns (string memory keyComponent) {
    return Strings.toHexString(account);
}

function bytes4ToKeyComponent(bytes4 value) pure returns (string memory keyComponent) {
    return Strings.toHexString(uint32(value), 4);
}

function bytes32ToKeyComponent(bytes32 value) pure returns (string memory keyComponent) {
    return Strings.toHexString(uint256(value), 32);
}

function int256ToKeyComponent(int256 value) pure returns (string memory keyComponent) {
    return Strings.toStringSigned(value);
}

function uint256ToKeyComponent(uint256 value) pure returns (string memory keyComponent) {
    return Strings.toString(value);
}
