// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../UnitTestBase.t.sol";

import { RateLimits, IRateLimits }         from "../../../src/RateLimits.sol";
import { RateLimitHelpers, RateLimitData } from "../../../src/RateLimitHelpers.sol";

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

    function unlimitedRateLimit() public pure returns (RateLimitData memory) {
        return RateLimitHelpers.unlimitedRateLimit();
    }

    function setRateLimitData(
        bytes32 key,
        address rateLimits,
        RateLimitData memory data,
        string memory name,
        uint256 decimals
    )
        public
    {
        RateLimitHelpers.setRateLimitData(key, rateLimits, data, name, decimals);
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

    function test_unlimitedRateLimit() public view {
        RateLimitData memory data = wrapper.unlimitedRateLimit();

        assertEq(data.maxAmount, type(uint256).max);
        assertEq(data.slope,     0);
    }

}

contract RateLimitHelpersSetRateLimitDataFailureTests is RateLimitHelpersTestBase {

    function test_setRateLimitData_unlimitedWithNonZeroSlope() external {
        RateLimitData memory data = RateLimitData({
            maxAmount : type(uint256).max,
            slope     : 1
        });

        vm.expectRevert(abi.encodeWithSignature(
            "InvalidUnlimitedRateLimitSlope(string)",
            NAME
        ));
        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);
    }

    function test_setRateLimitData_maxAmountUpperBoundBoundary() external {
        // Set 1e18 precision value on a 6 decimal token
        RateLimitData memory data = RateLimitData({
            maxAmount : 1e18 + 1,
            slope     : 0
        });

        vm.expectRevert(abi.encodeWithSignature(
            "InvalidMaxAmountPrecision(string)",
            NAME
        ));
        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 6);

        data.maxAmount = 1e18;

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 6);
    }

    function test_setRateLimitData_maxAmountLowerBoundBoundary() external {
        // Set 1e6 precision value on a 18 decimal token
        RateLimitData memory data = RateLimitData({
            maxAmount : 1_000_000_000_000e6 - 1,
            slope     : 0
        });

        vm.expectRevert(abi.encodeWithSignature(
            "InvalidMaxAmountPrecision(string)",
            NAME
        ));
        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);

        data.maxAmount = 1_000_000_000_000e6;

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);
    }

    function test_setRateLimitData_slopeUpperBoundBoundary() external {
        // Set 1e18 precision value on a 6 decimal token
        RateLimitData memory data = RateLimitData({
            maxAmount : 100e6,
            slope     : uint256(1e18) / 1 hours + 1
        });

        vm.expectRevert(abi.encodeWithSignature(
            "InvalidSlopePrecision(string)",
            NAME
        ));
        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 6);

        data.slope = uint256(1e18) / 1 hours;

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 6);
    }

    function test_setRateLimitData_slopeLowerBoundBoundary() external {
        // Set 1e6 precision value on a 18 decimal token
        RateLimitData memory data = RateLimitData({
            maxAmount : 100e18,
            slope     : uint256(1_000_000_000_000e6) / 1 hours - 1
        });

        vm.expectRevert(abi.encodeWithSignature(
            "InvalidSlopePrecision(string)",
            NAME
        ));
        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);

        data.slope = uint256(1_000_000_000_000e6) / 1 hours;

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);
    }

}

contract RateLimitHelpersSetRateLimitDataSuccessTests is RateLimitHelpersTestBase {

    function test_setRateLimitData_unlimited() external {
        RateLimitData memory data = RateLimitData({
            maxAmount : type(uint256).max,
            slope     : 0
        });

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);

        _assertLimitData(KEY, type(uint256).max, 0, type(uint256).max, block.timestamp);
    }

    function test_setRateLimitData() external {
        RateLimitData memory data = RateLimitData({
            maxAmount : 100e18,
            slope     : uint256(1e18) / 1 hours
        });

        wrapper.setRateLimitData(KEY, address(rateLimits), data, NAME, 18);

        _assertLimitData(KEY, 100e18, uint256(1e18) / 1 hours, 100e18, block.timestamp);
    }

}
