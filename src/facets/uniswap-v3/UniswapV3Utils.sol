// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

// Use dss-allocator instead of Uniswap implementations to be compatible with Solidity 0.8.xx
import { FixedPoint96 } from "../../../lib/dss-allocator/src/funnels/uniV3/LiquidityAmounts.sol";
import { FullMath }     from "../../../lib/dss-allocator/src/funnels/uniV3/FullMath.sol";

interface IUniswapV3PoolLike {

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX96);

}

library SafeCast {

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SafeCast.sol#L24
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }

}

library UniswapV3Utils {

    using SafeCast for uint256;

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/UnsafeMath.sol#L12
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SqrtPriceMath.sol#L153
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool    roundUp
    )
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
                ? divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SqrtPriceMath.sol#L182
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool    roundUp
    )
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        return
            roundUp
                ? FullMath.mulDivRoundingUp(
                    liquidity,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    FixedPoint96.Q96
                )
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SqrtPriceMath.sol#L201
    function getAmount0Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        internal
        pure
        returns (int256 amount0)
    {
        return
            liquidity < 0
                ? -getAmount0Delta(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    uint128(-liquidity),
                    false
                ).toInt256()
                : getAmount0Delta(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    uint128(liquidity),
                    true
                ).toInt256();
    }

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SqrtPriceMath.sol#L217
    function getAmount1Delta(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        internal
        pure
        returns (int256 amount1)
    {
        return
            liquidity < 0
                ? -getAmount1Delta(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    uint128(-liquidity),
                    false
                ).toInt256()
                : getAmount1Delta(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    uint128(liquidity),
                    true
                ).toInt256();
    }

    /**
     * Taken from
     * https://github.com/Uniswap/v3-periphery/blob/v1.3.0/contracts/libraries/OracleLibrary.sol
     * @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
     * @param  pool                  Address of the pool that we want to observe.
     * @param  secondsAgo            Number of seconds in the past from which to calculate the
     *                               time-weighted means.
     * @return arithmeticMeanTick    The arithmetic mean tick from (block.timestamp - secondsAgo)
     *                               to block.timestamp.
     * @return harmonicMeanLiquidity The harmonic mean liquidity from (block.timestamp - secondsAgo)
     *                               to block.timestamp.
     * Changes: changed the require message, explicitly cast secondsAgo to int32, and
     *          UniswapV3PoolLike to IUniswapV3PoolLike.
     */
    function consult(address pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        require(secondsAgo != 0, 'UniswapV3Facet/consult-seconds-ago-not-zero');

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0]              = secondsAgo;
        secondsAgos[1]              = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            IUniswapV3PoolLike(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        uint160 secondsPerLiquidityCumulativesDelta =
            secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int32(secondsAgo));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0)) {
            arithmeticMeanTick--;
        }

        // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
        uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;

        harmonicMeanLiquidity = uint128(
            secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32)
        );
    }

}
