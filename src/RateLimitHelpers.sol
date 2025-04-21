// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IRateLimits } from "../src/interfaces/IRateLimits.sol";

struct RateLimitData {
    uint256 maxAmount;
    uint256 slope;
}

library RateLimitHelpers {

    error InvalidUnlimitedRateLimitSlope(string name);
    error InvalidMaxAmountPrecision(string name);
    error InvalidSlopePrecision(string name);

    function makeAssetKey(bytes32 key, address asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, asset));
    }

    function makeAssetDestinationKey(bytes32 key, address asset, address destination) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, asset, destination));
    }

    function makeDomainKey(bytes32 key, uint32 domain) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, domain));
    }

    function unlimitedRateLimit() internal pure returns (RateLimitData memory) {
        return RateLimitData({
            maxAmount : type(uint256).max,
            slope     : 0
        });
    }

}
