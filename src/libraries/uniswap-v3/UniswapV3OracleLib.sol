// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

// Use dss-allocator instead of Uniswap implementations to be compatible with Solidity 0.8.xx
import { FullMath } from "../../../lib/dss-allocator/src/funnels/uniV3/FullMath.sol";
import { TickMath } from "../../../lib/dss-allocator/src/funnels/uniV3/TickMath.sol";

interface IUniswapV3PoolLike {

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX96);

}

library UniswapV3OracleLib {

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
