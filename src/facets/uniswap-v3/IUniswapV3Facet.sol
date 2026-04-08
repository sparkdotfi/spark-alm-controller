// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IUniswapV3Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Ticks {
        int24 lower;
        int24 upper;
    }

    struct TokenAmounts {
        uint256 amount0;
        uint256 amount1;
    }

    struct PoolParams {
        uint24 swapMaxTickDelta;
        Ticks  liquidityTickBounds;
        uint32 twapSecondsAgo;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event UniswapV3AddLiquidity(
        address indexed pool,
        uint256 indexed tokenId,
        int24           tickLower,
        int24           tickUpper,
        uint128         liquidity,
        uint256         amount0,
        uint256         amount1
    );

    event UniswapV3LowerTickUpdated(address indexed pool, int24 lowerTick);

    event UniswapV3MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event UniswapV3MaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);

    event UniswapV3RemoveLiquidity(
        address indexed pool,
        uint256 indexed tokenId,
        uint128         liquidity,
        uint256         amount0,
        uint256         amount1
    );

    event UniswapV3Swap(
        address indexed pool,
        address indexed tokenIn,
        uint256         amountInSpent,
        uint256         amountOut
    );

    event UniswapV3TWAPSecondsAgoUpdated(address indexed pool, uint32 twapSecondsAgo);

    event UniswapV3UpperTickUpdated(address indexed pool, int24 upperTick);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function addLiquidity(
        address               pool,
        uint256               tokenId,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        external
        returns (uint256 tokenId_, uint128 liquidity_, TokenAmounts memory amounts_);

    function removeLiquidity(
        address               pool,
        uint256               tokenId,
        uint128               liquidity,
        TokenAmounts calldata min,
        uint256               deadline
    )
        external
        returns (TokenAmounts memory amounts);

    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    function setMaxTickDelta(address pool, uint24 maxTickDelta) external;

    function setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    function setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    function setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    function swap(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        external
        returns (uint256 amountOut);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_SWAP() external pure returns (bytes32);

    function LIMIT_WITHDRAW() external pure returns (bytes32);

    function MAX_TICK_DELTA() external pure returns (uint24);

    function MIN_TICK() external pure returns (int24);

    function MAX_TICK() external pure returns (int24);

    function positionManager() external view returns (address);

    function router() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getMaxSlippage(address pool) external view returns (uint256);

    function getMaxTickDelta(address pool) external view returns (uint24);

    function getLiquidityTickBounds(address pool) external view returns (int24 lower, int24 upper);

    function getTWAPSecondsAgo(address pool) external view returns (uint32);

}
