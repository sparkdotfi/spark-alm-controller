// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IRateLimits } from "../src/interfaces/IRateLimits.sol";

struct RateLimitData {
    uint256 maxAmount;
    uint256 slope;
}

library RateLimitHelpers {

    function makeAssetKey(bytes32 key, address asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, asset));
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
            require(
                data.slope == 0,
                string(abi.encodePacked("RateLimitHelpers/invalid-rate-limit-", name))
            );
        }
        else {
            require(
                data.maxAmount <= 1e12 * (10 ** decimals),
                string(abi.encodePacked("RateLimitHelpers/invalid-max-amount-precision-", name))
            );
            require(
                data.slope <= 1e12 * (10 ** decimals) / 1 hours,
                string(abi.encodePacked("RateLimitHelpers/invalid-slope-precision-", name))
            );
        }
        IRateLimits(rateLimits).setRateLimitData(key, data.maxAmount, data.slope);
    }

}
