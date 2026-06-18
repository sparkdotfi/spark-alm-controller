// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { UniswapV3Utils, SafeCast } from "../../src/facets/uniswap-v3/UniswapV3Utils.sol";

// Wrapper contract to expose library internals for testing
contract UniswapV3UtilsHarness {

    using UniswapV3Utils for *;

    function divRoundingUp(uint256 x, uint256 y) external pure returns (uint256) {
        return UniswapV3Utils.divRoundingUp(x, y);
    }

    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool    roundUp
    ) external pure returns (uint256) {
        return UniswapV3Utils.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    }

    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool    roundUp
    ) external pure returns (uint256) {
        return UniswapV3Utils.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, roundUp);
    }

    function getAmount0DeltaSigned(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128  liquidity
    ) external pure returns (int256) {
        return UniswapV3Utils.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function getAmount1DeltaSigned(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128  liquidity
    ) external pure returns (int256) {
        return UniswapV3Utils.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

}

contract SafeCastHarness {

    function toInt256(uint256 y) external pure returns (int256) {
        return SafeCast.toInt256(y);
    }

}

contract UniswapV3Utils_DivRoundingUp_Tests is Test {

    UniswapV3UtilsHarness internal harness;

    function setUp() public {
        harness = new UniswapV3UtilsHarness();
    }

    function test_divRoundingUp_exactDivision() external view {
        assertEq(harness.divRoundingUp(10, 5), 2);
    }

    function test_divRoundingUp_roundsUp() external view {
        assertEq(harness.divRoundingUp(11, 5), 3);
    }

    function test_divRoundingUp_zeroNumerator() external view {
        assertEq(harness.divRoundingUp(0, 5), 0);
    }

    function test_divRoundingUp_one() external view {
        assertEq(harness.divRoundingUp(1, 1), 1);
    }

}

contract UniswapV3Utils_GetAmount0Delta_Tests is Test {

    UniswapV3UtilsHarness internal harness;

    // Use realistic sqrtPrice values (Q96 format)
    // sqrtPrice for price=1 is 2^96 ≈ 79228162514264337593543950336
    uint160 internal constant SQRT_PRICE_1    = 79228162514264337593543950336;
    // sqrtPrice for price=1.01 ≈ 79625483285009044410665803269
    uint160 internal constant SQRT_PRICE_1_01 = 79625483285009044410665803269;

    function setUp() public {
        harness = new UniswapV3UtilsHarness();
    }

    function test_getAmount0Delta_roundUp() external view {
        uint256 amount = harness.getAmount0Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        assertGt(amount, 0);
    }

    function test_getAmount0Delta_roundDown() external view {
        uint256 amountUp   = harness.getAmount0Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        uint256 amountDown = harness.getAmount0Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, false);
        assertGe(amountUp, amountDown);
    }

    function test_getAmount0Delta_swappedPrices() external view {
        // When A > B, should swap internally and return same result
        uint256 amount1 = harness.getAmount0Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        uint256 amount2 = harness.getAmount0Delta(SQRT_PRICE_1_01, SQRT_PRICE_1, 1e18, true);
        assertEq(amount1, amount2);
    }

    function test_getAmount0DeltaSigned_positiveLiquidity() external view {
        int256 amount = harness.getAmount0DeltaSigned(SQRT_PRICE_1, SQRT_PRICE_1_01, int128(1e18));
        assertGt(amount, 0);
    }

    function test_getAmount0DeltaSigned_negativeLiquidity() external view {
        int256 amount = harness.getAmount0DeltaSigned(SQRT_PRICE_1, SQRT_PRICE_1_01, -int128(1e18));
        assertLt(amount, 0);
    }

}

contract UniswapV3Utils_GetAmount1Delta_Tests is Test {

    UniswapV3UtilsHarness internal harness;

    uint160 internal constant SQRT_PRICE_1    = 79228162514264337593543950336;
    uint160 internal constant SQRT_PRICE_1_01 = 79625483285009044410665803269;

    function setUp() public {
        harness = new UniswapV3UtilsHarness();
    }

    function test_getAmount1Delta_roundUp() external view {
        uint256 amount = harness.getAmount1Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        assertGt(amount, 0);
    }

    function test_getAmount1Delta_roundDown() external view {
        uint256 amountUp   = harness.getAmount1Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        uint256 amountDown = harness.getAmount1Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, false);
        assertGe(amountUp, amountDown);
    }

    function test_getAmount1Delta_swappedPrices() external view {
        uint256 amount1 = harness.getAmount1Delta(SQRT_PRICE_1, SQRT_PRICE_1_01, 1e18, true);
        uint256 amount2 = harness.getAmount1Delta(SQRT_PRICE_1_01, SQRT_PRICE_1, 1e18, true);
        assertEq(amount1, amount2);
    }

    function test_getAmount1DeltaSigned_positiveLiquidity() external view {
        int256 amount = harness.getAmount1DeltaSigned(SQRT_PRICE_1, SQRT_PRICE_1_01, int128(1e18));
        assertGt(amount, 0);
    }

    function test_getAmount1DeltaSigned_negativeLiquidity() external view {
        int256 amount = harness.getAmount1DeltaSigned(SQRT_PRICE_1, SQRT_PRICE_1_01, -int128(1e18));
        assertLt(amount, 0);
    }

}

contract SafeCast_ToInt256_Tests is Test {

    SafeCastHarness internal harness;

    function setUp() public {
        harness = new SafeCastHarness();
    }

    function test_toInt256_zero() external view {
        assertEq(harness.toInt256(0), 0);
    }

    function test_toInt256_maxValid() external view {
        uint256 maxVal = uint256(type(int256).max);
        assertEq(harness.toInt256(maxVal), type(int256).max);
    }

    function test_toInt256_overflow() external {
        uint256 tooLarge = uint256(2 ** 255);
        vm.expectRevert();
        harness.toInt256(tooLarge);
    }

}
