// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "v4-core/libraries/FullMath.sol";
import "v4-core/libraries/FixedPoint96.sol";

library LiquidityAmounts {

    function getAmount0ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib: sqrtPriceA must be < sqrtPriceB");
        return FullMath.mulDiv(uint256(liquidity) << 96, sqrtPriceBX96 - sqrtPriceAX96, uint256(sqrtPriceBX96) * sqrtPriceAX96);
    }

    function getAmount1ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib: sqrtPriceA must be < sqrtPriceB");
        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, 1 << 96);
    }

    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib: sqrtPriceA must be < sqrtPriceB");

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
            return (amount0, 0);
        }
        if (sqrtPriceX96 < sqrtPriceBX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity);
            return (amount0, amount1);
        }
        if (sqrtPriceX96 >= sqrtPriceBX96) {
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
            return (0, amount1);
        }
        revert("UniswapV4Lib: unreachable");
    }

}
