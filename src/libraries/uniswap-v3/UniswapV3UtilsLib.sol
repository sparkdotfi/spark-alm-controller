// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { FixedPoint96 } from "../../../lib/dss-allocator/src/funnels/uniV3/LiquidityAmounts.sol";
import { FullMath }     from "../../../lib/dss-allocator/src/funnels/uniV3/FullMath.sol";

library SafeCast {

    // https://github.com/Uniswap/v3-core/blob/v1.0.0/contracts/libraries/SafeCast.sol#L24
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }

}

library UniswapV3UtilsLib {

    using SafeCast for uint256;
    using SafeCast for int256;

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
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128  liquidity
    ) internal pure returns (int256 amount0) {
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
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128  liquidity
    ) internal pure returns (int256 amount1) {
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

}
