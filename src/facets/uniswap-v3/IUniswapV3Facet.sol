// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IUniswapV3Facet
 * @notice PAU facet for interacting with Uniswap V3 pools. Supports adding/removing concentrated
 *         liquidity positions, and exact-input token swaps via the Uniswap V3 SwapRouter.
 */
interface IUniswapV3Facet is IFacet {

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

    /**
     * @notice Emitted when liquidity is added to a Uniswap V3 position.
     * @param  pool      Address of the Uniswap V3 pool.
     * @param  tokenId   NFT token ID of the liquidity position.
     * @param  tickLower Lower tick of the position range.
     * @param  tickUpper Upper tick of the position range.
     * @param  liquidity Amount of liquidity added.
     * @param  amount0   Amount of token0 deposited.
     * @param  amount1   Amount of token1 deposited.
     */
    event UniswapV3AddLiquidity(
        address indexed pool,
        uint256 indexed tokenId,
        int24           tickLower,
        int24           tickUpper,
        uint128         liquidity,
        uint256         amount0,
        uint256         amount1
    );

    /**
     * @notice Emitted when the lower tick bound for a pool is updated.
     * @param  pool      Address of the Uniswap V3 pool.
     * @param  lowerTick New lower tick bound for liquidity positions.
     */
    event UniswapV3LowerTickSet(address indexed pool, int24 lowerTick);

    /**
     * @notice Emitted when the max slippage for a pool is updated.
     * @param  pool        Address of the Uniswap V3 pool.
     * @param  maxSlippage New max slippage in 1e18 precision (1e18 = no slippage).
     */
    event UniswapV3MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    /**
     * @notice Emitted when the max tick delta for swaps on a pool is updated.
     * @param  pool         Address of the Uniswap V3 pool.
     * @param  maxTickDelta New max allowed tick deviation from TWAP for swaps.
     */
    event UniswapV3MaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);

    /**
     * @notice Emitted when liquidity is removed from a Uniswap V3 position.
     * @param  pool      Address of the Uniswap V3 pool.
     * @param  tokenId   NFT token ID of the liquidity position.
     * @param  liquidity Amount of liquidity removed.
     * @param  amount0   Amount of token0 received.
     * @param  amount1   Amount of token1 received.
     */
    event UniswapV3RemoveLiquidity(
        address indexed pool,
        uint256 indexed tokenId,
        uint128         liquidity,
        uint256         amount0,
        uint256         amount1
    );

    /**
     * @notice Emitted when a token swap is executed on a Uniswap V3 pool.
     * @param  pool          Address of the Uniswap V3 pool.
     * @param  tokenIn       Address of the input token.
     * @param  amountInSpent Amount of input tokens spent.
     * @param  amountOut     Amount of output tokens received.
     */
    event UniswapV3Swap(
        address indexed pool,
        address indexed tokenIn,
        uint256         amountInSpent,
        uint256         amountOut
    );

    /**
     * @notice Emitted when the TWAP lookback period for a pool is updated.
     * @param  pool           Address of the Uniswap V3 pool.
     * @param  twapSecondsAgo New TWAP lookback duration in seconds.
     */
    event UniswapV3TWAPSecondsAgoSet(address indexed pool, uint32 twapSecondsAgo);

    /**
     * @notice Emitted when the upper tick bound for a pool is updated.
     * @param  pool      Address of the Uniswap V3 pool.
     * @param  upperTick New upper tick bound for liquidity positions.
     */
    event UniswapV3UpperTickSet(address indexed pool, int24 upperTick);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Adds liquidity to a Uniswap V3 position. If tokenId is 0, mints a new position;
     *        otherwise increases an existing one.
     * @param  pool     Address of the Uniswap V3 pool.
     * @param  tokenId  NFT token ID (0 to create a new position).
     * @param  ticks    Lower and upper tick bounds for the position.
     * @param  target   Target amounts of token0 and token1 to deposit.
     * @param  min      Minimum amounts of token0 and token1 to deposit.
     * @param  deadline Unix timestamp deadline for the transaction.
     */
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

    /**
     * @notice Removes liquidity from a Uniswap V3 position and collects tokens.
     * @param  pool      Address of the Uniswap V3 pool.
     * @param  tokenId   NFT token ID of the position.
     * @param  liquidity Amount of liquidity to remove.
     * @param  min       Minimum amounts of token0 and token1 to receive.
     * @param  deadline  Unix timestamp deadline for the transaction.
     */
    function removeLiquidity(
        address               pool,
        uint256               tokenId,
        uint128               liquidity,
        TokenAmounts calldata min,
        uint256               deadline
    )
        external
        returns (TokenAmounts memory amounts);

    /**
     * @notice Sets the max slippage for a Uniswap V3 pool.
     * @param  pool        Address of the Uniswap V3 pool.
     * @param  maxSlippage Max slippage in 1e18 precision (1e18 = no slippage).
     */
    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    /**
     * @notice Sets the max tick delta allowed for swaps on a pool. Limits how far the current tick
     *        can deviate from the TWAP tick.
     * @param  pool         Address of the Uniswap V3 pool.
     * @param  maxTickDelta Max allowed tick deviation from TWAP.
     */
    function setMaxTickDelta(address pool, uint24 maxTickDelta) external;

    /**
     * @notice Sets the lower tick bound for liquidity positions on a pool.
     * @param  pool           Address of the Uniswap V3 pool.
     * @param  lowerTickBound Minimum lower tick for positions.
     */
    function setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    /**
     * @notice Sets the upper tick bound for liquidity positions on a pool.
     * @param  pool           Address of the Uniswap V3 pool.
     * @param  upperTickBound Maximum upper tick for positions.
     */
    function setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    /**
     * @notice Sets the TWAP lookback period for a pool. Used to compute the time-weighted average
     *        tick for swap validation.
     * @param  pool           Address of the Uniswap V3 pool.
     * @param  twapSecondsAgo TWAP lookback duration in seconds.
     */
    function setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    /**
     * @notice Swaps tokens via the Uniswap V3 SwapRouter (exact input single).
     * @param  pool         Address of the Uniswap V3 pool.
     * @param  tokenIn      Address of the input token.
     * @param  amountIn     Amount of input tokens to swap.
     * @param  minAmountOut Minimum output tokens to receive.
     * @param  tickDelta    Max tick deviation from TWAP for this swap.
     * @return amountOut    Actual amount of output tokens received.
     */
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

    /// @notice Upper bound for the max tick delta admin parameter.
    function MAX_TICK_DELTA() external pure returns (uint24);

    /// @notice Uniswap V3 minimum tick value (from TickMath).
    function MIN_TICK() external pure returns (int24);

    /// @notice Uniswap V3 maximum tick value (from TickMath).
    function MAX_TICK() external pure returns (int24);

    /// @notice Address of the Uniswap V3 NonfungiblePositionManager (immutable).
    function positionManager() external view returns (address);

    /// @notice Address of the Uniswap V3 SwapRouter (immutable).
    function router() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived aggregate deposit rate limit key for a pool.
     * @param  pool Address of the Uniswap V3 pool.
     * @return key  Derived rate limit key.
     */
    function getAggregateDepositRateLimitKey(address pool) external pure returns (bytes32 key);

    /**
     * @notice Returns the derived deposit rate limit key for a pool and token.
     * @param  pool  Address of the Uniswap V3 pool.
     * @param  token Address of the token being deposited.
     * @return key   Derived rate limit key.
     */
    function getAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the configured tick bounds for liquidity positions.
     * @param  pool  Address of the pool.
     * @return lower Minimum lower tick bound.
     * @return upper Maximum upper tick bound.
     */
    function getLiquidityTickBounds(address pool) external view returns (int24 lower, int24 upper);

    /**
     * @notice Returns the configured max slippage for a Uniswap V3 pool.
     * @param  pool        Address of the pool.
     * @return maxSlippage Max slippage in 1e18 precision. Zero means not set.
     */
    function getMaxSlippage(address pool) external view returns (uint256 maxSlippage);

    /**
     * @notice Returns the configured max tick delta for swaps on a pool.
     * @param  pool         Address of the pool.
     * @return maxTickDelta Max tick delta. Zero means not set.
     */
    function getMaxTickDelta(address pool) external view returns (uint24 maxTickDelta);

    /**
     * @notice Returns the derived swap rate limit key for a pool and token.
     * @param  pool  Address of the Uniswap V3 pool.
     * @param  token Address of the token being swapped.
     * @return key   Derived rate limit key.
     */
    function getSwapRateLimitKey(address pool, address token) external pure returns (bytes32 key);

    /**
     * @notice Returns the configured TWAP lookback period for a pool.
     * @param  pool           Address of the pool.
     * @return twapSecondsAgo TWAP lookback duration in seconds. Zero means not set.
     */
    function getTWAPSecondsAgo(address pool) external view returns (uint32 twapSecondsAgo);

    /**
     * @notice Returns the derived withdraw rate limit key for a pool.
     * @param  pool Address of the Uniswap V3 pool.
     * @return key  Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

}
