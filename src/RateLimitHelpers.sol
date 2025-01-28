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

    function setRateLimitData(
        bytes32       key,
        address       rateLimits,
        RateLimitData memory data,
        string        memory name,
        uint256       decimals
    )
        internal
    {
        // Handle setting an unlimited rate limit
        if (data.maxAmount == type(uint256).max) {
            if (data.slope != 0) {
                revert InvalidUnlimitedRateLimitSlope(name);
            }
        } else {
            uint256 upperBound = 1e12 * (10 ** decimals);
            uint256 lowerBound = 10 ** decimals;

            if (data.maxAmount > upperBound || data.maxAmount < lowerBound) {
                revert InvalidMaxAmountPrecision(name);
            }

            if (
                data.slope != 0 &&
                (data.slope > upperBound / 1 hours || data.slope < lowerBound / 1 hours)
            ) {
                revert InvalidSlopePrecision(name);
            }
        }
        IRateLimits(rateLimits).setRateLimitData(key, data.maxAmount, data.slope);
    }

}
