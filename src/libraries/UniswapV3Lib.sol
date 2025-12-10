// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 }         from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { ERC20Lib } from "./common/ERC20Lib.sol";
import { MathLib }  from "./common/MathLib.sol";

import { UniV3UtilsLib, TickMath, LiquidityAmounts, FullMath } from "./uniswap-v3/UniV3UtilsLib.sol";
import { UniswapV3OracleLib }                                  from "./uniswap-v3/UniV3OracleLib.sol";

import { IALMProxy }                                                    from "../interfaces/IALMProxy.sol";
import { IRateLimits }                                                  from "../interfaces/IRateLimits.sol";
import { ISwapRouter, IUniswapV3PoolLike, INonfungiblePositionManager } from "../interfaces/UniswapV3Interfaces.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library UniswapV3Lib {
    uint24 public constant MAX_TICK_DELTA = 887272; // From https://github.com/sky-ecosystem/dss-allocator/blob/dev/src/funnels/uniV3/TickMath.sol#L15

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/
    struct Tick {
        int24 lower;
        int24 upper;
    }

    struct TokenAmounts {
        uint256 amount0;
        uint256 amount1;
    }

    struct UniswapV3PoolParams {
        uint24 swapMaxTickDelta;
        Tick   addLiquidityTickBounds;
        uint32 twapSecondsAgo;
    }

    struct UniV3Context {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        bytes32     rateLimitId;
        address     pool;
    }

    struct SwapParams {
        UniswapV3PoolParams poolParams;
        ISwapRouter         router;
        address             tokenIn;
        uint256             amountIn;
        uint256             minAmountOut;
        uint24              tickDelta; // The maximum that the tick can move by after completing the swap; cannot exceed MAX_TICK_DELTA
        uint256             maxSlippage;
    }

    struct SwapCache {
        address tokenOut;
        uint160 sqrtPriceLimitX96;
    }

    struct AddLiquidityParams {
        uint256                     tokenId; // 0 for a new position
        INonfungiblePositionManager positionManager;
        Tick                        tick;
        Tick                        tickBounds;
        TokenAmounts                target;
        TokenAmounts                min;
        uint256                     maxSlippage;
        uint256                     deadline;
        uint32                      twapSecondsAgo;
    }

    struct RemoveLiquidityParams {
        INonfungiblePositionManager positionManager;
        uint256                     tokenId;
        uint128                     liquidity;
        TokenAmounts                min;
        uint256                     maxSlippage;
        uint256                     deadline;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    // Rate limit decreased by value of tokenIn (the amount actually spent)
    function swap(UniV3Context calldata context, SwapParams calldata params) external returns (uint256 amountOut) {
        require(params.maxSlippage > 0,                                 "UniswapV3Lib/max-slippage-not-set");
        require(params.tickDelta <= params.poolParams.swapMaxTickDelta, "UniswapV3Lib/invalid-max-tick-delta");
        require(params.poolParams.twapSecondsAgo != 0,                  "UniswapV3Lib/zero-twap-seconds");

        SwapCache memory cache = _populateSwapCache(context, params);
        ERC20Lib.approve(context.proxy, params.tokenIn, address(params.router), params.amountIn);

        uint256 startingBalance = IERC20(params.tokenIn).balanceOf(address(context.proxy));
        amountOut               = _callSwap(context, params, cache);
        uint256 endingBalance   = IERC20(params.tokenIn).balanceOf(address(context.proxy));
        require(params.minAmountOut >= amountOut * params.maxSlippage / 1e18 , "UniswapV3Lib/min-amount-not-met");

        // Clear approvals of dust
        ERC20Lib.approve(context.proxy, params.tokenIn, address(params.router), 0);

        context.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetDestinationKey(context.rateLimitId, params.tokenIn, context.pool),
            startingBalance - endingBalance
        );
    }

    function addLiquidity(UniV3Context calldata context, AddLiquidityParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(
            params.target.amount0 > 0 || params.target.amount1 > 0,
            "UniswapV3Lib/zero-amount"
        );

        require(params.maxSlippage > 0,     "UniswapV3Lib/max-slippage-not-set");
        require(params.twapSecondsAgo != 0, "UniswapV3Lib/zero-twap-seconds");

        require(params.tick.lower >= params.tickBounds.lower, "UniswapV3Lib/lower-tick-outside-bounds");
        require(params.tick.upper <= params.tickBounds.upper, "UniswapV3Lib/upper-tick-outside-bounds");

        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);

        address token0 = pool.token0();
        address token1 = pool.token1();

        ERC20Lib.approve(context.proxy, token0, address(params.positionManager), params.target.amount0);
        ERC20Lib.approve(context.proxy, token1, address(params.positionManager), params.target.amount1);

        _validateAddLiquidityMinAmounts(context, params);

        uint256 startingBalance0 = IERC20(token0).balanceOf(address(context.proxy));
        uint256 startingBalance1 = IERC20(token1).balanceOf(address(context.proxy));

        if (params.tokenId == 0) {
            (tokenId, liquidity, amount0, amount1) = _mintLiquidity(context, params);
        } else {
            (tokenId, liquidity, amount0, amount1) = _addLiquidityToExistingPosition(context, params);
        }

        require(liquidity != 0, "UniswapV3Lib/no-liquidity-increased");

        {
            uint256 balanceDiff0 = startingBalance0 - IERC20(token0).balanceOf(address(context.proxy));
            uint256 balanceDiff1 = startingBalance1 - IERC20(token1).balanceOf(address(context.proxy));

            require(params.min.amount0 >= balanceDiff0 * params.maxSlippage / 1e18, "UniswapV3Lib/min-amount-below-bound");
            require(params.min.amount1 >= balanceDiff1 * params.maxSlippage / 1e18, "UniswapV3Lib/min-amount-below-bound");
        }

        // Clear approvals of dust
        ERC20Lib.approve(context.proxy, token0, address(params.positionManager), 0);
        ERC20Lib.approve(context.proxy, token1, address(params.positionManager), 0);

        context.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetDestinationKey(context.rateLimitId, token0, address(pool)),
            amount0
        );
        context.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetDestinationKey(context.rateLimitId, token1, address(pool)),
            amount1
        );
    }

    function removeLiquidity(UniV3Context calldata context, RemoveLiquidityParams calldata params)
        external
        returns (uint256 amount0Collected, uint256 amount1Collected)
    {
        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);

        (address token0, address token1) = _validateRemoveLiquidityParams(pool, params);
        require(params.positionManager.ownerOf(params.tokenId) == address(context.proxy), "UniswapV3Lib/proxy-does-not-own-token-id");

        uint256 amount0CollectedBefore = IERC20(token0).balanceOf(address(context.proxy));
        uint256 amount1CollectedBefore = IERC20(token1).balanceOf(address(context.proxy));

        _decreaseLiquidityCall(
            context.proxy,
            address(params.positionManager),
            params.tokenId,
            params.liquidity,
            params.min,
            params.deadline
        );

        (amount0Collected, amount1Collected) = _collectAll(
            context.proxy,
            address(params.positionManager),
            params.tokenId,
            address(context.proxy)
        );

        uint256 amount0CollectedAfter = IERC20(token0).balanceOf(address(context.proxy));
        uint256 amount1CollectedAfter = IERC20(token1).balanceOf(address(context.proxy));

        require(params.min.amount0 >= (amount0CollectedAfter - amount0CollectedBefore) * params.maxSlippage / 1e18, "UniswapV3Lib/min-amount-below-bound");
        require(params.min.amount1 >= (amount1CollectedAfter - amount1CollectedBefore) * params.maxSlippage / 1e18, "UniswapV3Lib/min-amount-below-bound");

        if (amount0Collected > 0) {
            context.rateLimits.triggerRateLimitDecrease(
                RateLimitHelpers.makeAssetDestinationKey(context.rateLimitId, token0, context.pool),
                amount0Collected
            );
        }
        if (amount1Collected > 0) {
            context.rateLimits.triggerRateLimitDecrease(
                RateLimitHelpers.makeAssetDestinationKey(context.rateLimitId, token1, context.pool),
                amount1Collected
            );
        }
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    //-- Swap helper functions
    function _populateSwapCache(UniV3Context calldata context, SwapParams calldata params) internal view returns (SwapCache memory cache) {
        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);
        address token0          = pool.token0();
        address token1          = pool.token1();

        require(
            params.tokenIn == token0 || params.tokenIn == token1,
            "UniswapV3Lib/invalid-token-pair"
        );

        // Fetch twap tick
        (int24 twapTick, ) = UniswapV3OracleLib.consult(context.pool, params.poolParams.twapSecondsAgo);

        cache.tokenOut = params.tokenIn == token0 ? token1 : token0;

        int24 delta = int24(params.tickDelta);
        int24 limitTick;
        if (params.tokenIn == token0) {
            limitTick = MathLib._max(twapTick - delta, TickMath.MIN_TICK);
        } else {
            limitTick = MathLib._min(twapTick + delta, TickMath.MAX_TICK);
        }

        cache.sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(limitTick);

        return cache;
    }

    function _callSwap(UniV3Context calldata context, SwapParams calldata params, SwapCache memory cache) internal returns (uint256 amountOut) {
        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);

        bytes memory result = context.proxy.doCall(
            address(params.router),
            abi.encodeWithSelector(
                ISwapRouter.exactInputSingle.selector,
                ISwapRouter.ExactInputSingleParams({
                    tokenIn           : params.tokenIn,
                    tokenOut          : cache.tokenOut,
                    fee               : pool.fee(),
                    recipient         : address(context.proxy),
                    amountIn          : params.amountIn,
                    amountOutMinimum  : params.minAmountOut,
                    sqrtPriceLimitX96 : cache.sqrtPriceLimitX96
                })
            )
        );

        amountOut = abi.decode(result, (uint256));
    }

    //-- Add liquidity functions
    function _mintLiquidity(UniV3Context calldata context, AddLiquidityParams calldata params)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {

        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);

        int24 tickSpacing = pool.tickSpacing();

        // Validate that lower and upper ticks are correctly spaced
        require(params.tick.lower % tickSpacing == 0, "UniswapV3Lib/invalid-lower-tick");
        require(params.tick.upper % tickSpacing == 0, "UniswapV3Lib/invalid-upper-tick");

        INonfungiblePositionManager.MintParams memory mintParams
            = INonfungiblePositionManager.MintParams({
                token0         : pool.token0(),
                token1         : pool.token1(),
                fee            : pool.fee(),
                tickLower      : params.tick.lower,
                tickUpper      : params.tick.upper,
                recipient      : address(context.proxy),
                amount0Desired : params.target.amount0,
                amount1Desired : params.target.amount1,
                amount0Min     : params.min.amount0,
                amount1Min     : params.min.amount1,
                deadline       : params.deadline
            });

        bytes memory result = context.proxy.doCall(
            address(params.positionManager),
            abi.encodeCall(
                INonfungiblePositionManager.mint,
                (mintParams)
            )
        );

        (tokenId, liquidity, amount0, amount1) = abi.decode(result, (uint256, uint128, uint256, uint256));
    }

    function _addLiquidityToExistingPosition(UniV3Context calldata context, AddLiquidityParams calldata params)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.positionManager.ownerOf(params.tokenId) == address(context.proxy), "UniswapV3Lib/proxy-does-not-own-token-id");

        (address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, ) = _fetchPositionData(params.tokenId, params.positionManager);

        IUniswapV3PoolLike pool = IUniswapV3PoolLike(context.pool);

        require(pool.token0() == token0 && pool.token1() == token1 && pool.fee() == fee, "UniswapV3Lib/invalid-pool");

        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams
            = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId        : params.tokenId,
                amount0Desired : params.target.amount0,
                amount1Desired : params.target.amount1,
                amount0Min     : params.min.amount0,
                amount1Min     : params.min.amount1,
                deadline       : params.deadline
            });

        bytes memory result = context.proxy.doCall(
            address(params.positionManager),
            abi.encodeCall(
                INonfungiblePositionManager.increaseLiquidity,
                (increaseLiquidityParams)
            )
        );

        (liquidity, amount0, amount1) = abi.decode(result, (uint128, uint256, uint256));
        tokenId = params.tokenId;
    }

    // Fetches only the position data that we need
    function _fetchPositionData(
        uint256 tokenId,
        INonfungiblePositionManager positionManager
    ) internal view returns (
        address payable token0,
        address payable token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) {
        bytes memory positionData = abi.encodeCall(
            INonfungiblePositionManager.positions,
            tokenId
        );

        (bool success, bytes memory result) = address(positionManager).staticcall(positionData);

        require(success,              "UniswapV3Lib/positions-call-failed");
        require(result.length >= 384, "UniswapV3Lib/invalid-positions-return-data");

        assembly {
            // pointer to the first return slot (nonce)
            let data := add(result, 32)

            // --- ABI return layout (each 32 bytes) ---
            // word 0: nonce
            // word 1: operator
            // word 2: token0
            // word 3: token1
            // word 4: fee
            // word 5: tickLower
            // word 6: tickUpper
            // word 7: liquidity
            // -----------------------------------------

            token0    := mload(add(data, 64))   // word 2
            token1    := mload(add(data, 96))   // word 3
            fee       := mload(add(data, 128))  // word 4
            tickLower := mload(add(data, 160))  // word 5
            tickUpper := mload(add(data, 192))  // word 6
            liquidity := mload(add(data, 224))  // word 7

            // Sign-extend from int24 to int256 for proper handling
            // If bit 23 is set (negative), extend with 1s, otherwise with 0s
            tickLower := signextend(2, tickLower)  // 2 = 24 bits - 1 byte (3 bytes total, 0-indexed = 2)
            tickUpper := signextend(2, tickUpper)
        }
    }

    function _validateAddLiquidityMinAmounts(UniV3Context calldata context, AddLiquidityParams calldata params) internal view {
        // Fetch twap tick
        (int24 twapTick, ) = UniswapV3OracleLib.consult(context.pool, params.twapSecondsAgo);

        uint160 sqrtTwapPriceX96   = TickMath.getSqrtRatioAtTick(twapTick);
        uint160 sqrtRatioLowerX96  = TickMath.getSqrtRatioAtTick(params.tick.lower);
        uint160 sqrtRatioUpperX96  = TickMath.getSqrtRatioAtTick(params.tick.upper);

        uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtTwapPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96,
            params.target.amount0,
            params.target.amount1
        );

        uint256 expectedAmount0;
        uint256 expectedAmount1;

        if (twapTick <= params.tick.lower) {
            expectedAmount0 = UniV3UtilsLib.getAmount0Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );
        } else if (twapTick >= params.tick.upper) {
            expectedAmount1 = UniV3UtilsLib.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );
        } else {
            expectedAmount0 = UniV3UtilsLib.getAmount0Delta(
                sqrtTwapPriceX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );

            expectedAmount1 = UniV3UtilsLib.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtTwapPriceX96,
                expectedLiquidity,
                false
            );
        }

        _validateMinAmount(params.min.amount0, expectedAmount0, params.maxSlippage);
        _validateMinAmount(params.min.amount1, expectedAmount1, params.maxSlippage);
    }

    function _validateMinAmount(uint256 minAmount, uint256 expectedAmount, uint256 maxSlippage) internal pure {
        if (expectedAmount == 0) {
            require(minAmount == 0, "UniswapV3Lib/min-amount-below-bound");
            return;
        }
        uint256 minAmountThreshold = FullMath.mulDiv(expectedAmount, maxSlippage, 1e18);
        require(minAmount >= minAmountThreshold, "UniswapV3Lib/min-amount-below-bound");
    }

    function _validateRemoveLiquidityParams(IUniswapV3PoolLike pool, RemoveLiquidityParams calldata params) internal view returns (address token0, address token1) {
        token0     = pool.token0();
        token1     = pool.token1();
        uint24 fee = pool.fee();

        (
            address positionToken0,
            address positionToken1,
            uint24  positionFee,
            ,
            ,
            uint128 positionLiquidity
        ) = _fetchPositionData(params.tokenId, params.positionManager);

        require(positionToken0 == token0 && positionToken1 == token1 && positionFee == fee, "UniswapV3Lib/invalid-pool");
        require(params.liquidity > 0 && params.liquidity <= positionLiquidity,              "UniswapV3Lib/liquidity-out-of-bounds");
    }

    function _decreaseLiquidityCall(
        IALMProxy           proxy,
        address             positionManager,
        uint256             tokenId,
        uint128             liquidity,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
    {
        proxy.doCall(
            positionManager,
            abi.encodeWithSelector(
                INonfungiblePositionManager.decreaseLiquidity.selector,
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId    : tokenId,
                    liquidity  : liquidity,
                    amount0Min : min.amount0,
                    amount1Min : min.amount1,
                    deadline   : deadline
                })
            )
        );
    }

    function _collectAll(
        IALMProxy proxy,
        address positionManager,
        uint256 tokenId,
        address recipient
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        bytes memory result = proxy.doCall(
            positionManager,
            abi.encodeWithSelector(
                INonfungiblePositionManager.collect.selector,
                INonfungiblePositionManager.CollectParams({
                    tokenId    : tokenId,
                    recipient  : recipient,
                    amount0Max : type(uint128).max,
                    amount1Max : type(uint128).max
                })
            )
        );

        (amount0, amount1) = abi.decode(result, (uint256, uint256));
    }
}
