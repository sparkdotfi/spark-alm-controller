// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../UnitTestBase.t.sol";

import { RateLimits, IRateLimits } from "../../../src/RateLimits.sol";
import { RateLimitHelpers }        from "../../../src/RateLimitHelpers.sol";

contract RateLimitHelpersWrapper {

    function makeAssetKey(bytes32 key, address asset) public pure returns (bytes32) {
        return RateLimitHelpers.makeAssetKey(key, asset);
    }

    function makeAssetDestinationKey(bytes32 key, address asset, address destination) public pure returns (bytes32) {
        return RateLimitHelpers.makeAssetDestinationKey(key, asset, destination);
    }

    function makeDomainKey(bytes32 key, uint32 domain) public pure returns (bytes32) {
        return RateLimitHelpers.makeDomainKey(key, domain);
    }

}

contract RateLimitHelpersTestBase is UnitTestBase {

    bytes32 constant KEY  = "KEY";
    string  constant NAME = "NAME";

    address controller = makeAddr("controller");

    RateLimits              rateLimits;
    RateLimitHelpersWrapper wrapper;

    function setUp() public {
        // Set wrapper as admin so it can set rate limits
        wrapper    = new RateLimitHelpersWrapper();
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

}

contract RateLimitHelpersPureFunctionTests is RateLimitHelpersTestBase {

    function test_makeAssetKey() public view {
        assertEq(
            wrapper.makeAssetKey(KEY, address(this)),
            keccak256(abi.encode(KEY, address(this)))
        );
    }

    function test_makeAssetDestinationKey() public view {
        assertEq(
            wrapper.makeAssetDestinationKey(KEY, address(this), address(0)),
            keccak256(abi.encode(KEY, address(this), address(0)))
        );
    }

    function test_makeDomainKey() public view {
        assertEq(
            wrapper.makeDomainKey(KEY, 123),
            keccak256(abi.encode(KEY, 123))
        );
    }

}
