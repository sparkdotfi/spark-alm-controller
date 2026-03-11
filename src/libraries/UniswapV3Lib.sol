// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { LiquidityAmounts } from "../../lib/dss-allocator/src/funnels/uniV3/LiquidityAmounts.sol";
import { TickMath }         from "../../lib/dss-allocator/src/funnels/uniV3/TickMath.sol";

import { UniswapV3UtilsLib, FullMath } from "./uniswap-v3/UniswapV3UtilsLib.sol";
import { UniswapV3OracleLib }          from "./uniswap-v3/UniswapV3OracleLib.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressAddressKey } from "../RateLimitHelpers.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface ISwapRouter {

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

}

interface IUniswapV3PoolLike {

    function fee() external view returns (uint24);

    function tickSpacing() external view returns (int24);

    function token0() external view returns (address);

    function token1() external view returns (address);

}

interface INonfungiblePositionManager {

    struct MintParams {
        address token0;
        address token1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96  nonce,
            address operator,
            address token0,
            address token1,
            uint24  fee,
            int24   tickLower,
            int24   tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

}

library UniswapV3Lib {

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
        Ticks  addLiquidityTickBounds;
        uint32 twapSecondsAgo;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event UniswapV3PoolMaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);

    event UniswapV3PoolLowerTickUpdated(address indexed pool, int24 lowerTick);

    event UniswapV3PoolUpperTickUpdated(address indexed pool, int24 upperTick);

    event UniswapV3PoolTWAPSecondsAgoUpdated(address indexed pool, uint32 twapSecondsAgo);

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V3_DEPOSIT");
    bytes32 public constant LIMIT_SWAP     = keccak256("LIMIT_UNISWAP_V3_SWAP");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V3_WITHDRAW");

    // https://github.com/sky-ecosystem/dss-allocator/blob/dev/src/funnels/uniV3/TickMath.sol#L15
    uint24 public constant MAX_TICK_DELTA = 887_272;

    // https://github.com/uniswap/v4-core/blob/v4.0.0/src/libraries/TickMath.sol#L18-L23
    int24 public constant MIN_TICK = -887_272;
    int24 public constant MAX_TICK =  887_272;

    /**********************************************************************************************/
    /*** Setters                                                                                ***/
    /**********************************************************************************************/

    function setPoolMaxTickDelta(
        address pool,
        uint24  maxTickDelta,
        mapping (address => PoolParams) storage poolParams
    )
        external
    {
        require(
            maxTickDelta > 0 && maxTickDelta <= MAX_TICK_DELTA,
            "UniswapV3Lib/max-tick-delta-oob"
        );

        poolParams[pool].swapMaxTickDelta = maxTickDelta;

        emit UniswapV3PoolMaxTickDeltaSet(pool, maxTickDelta);
    }

    function setAddLiquidityLowerTickBound(
        address pool,
        int24   lowerTickBound,
        mapping (address => PoolParams) storage poolParams
    )
        external
    {
        require(
            lowerTickBound >= MIN_TICK &&
            lowerTickBound < poolParams[pool].addLiquidityTickBounds.upper,
            "UniswapV3Lib/lower-tick-oob"
        );

        poolParams[pool].addLiquidityTickBounds.lower = lowerTickBound;

        emit UniswapV3PoolLowerTickUpdated(pool, lowerTickBound);
    }

    function setAddLiquidityUpperTickBound(
        address pool,
        int24   upperTickBound,
        mapping (address => PoolParams) storage poolParams
    )
        external
    {
        require(
            upperTickBound <= MAX_TICK &&
            upperTickBound > poolParams[pool].addLiquidityTickBounds.lower,
            "UniswapV3Lib/upper-tick-oob"
        );

        poolParams[pool].addLiquidityTickBounds.upper = upperTickBound;

        emit UniswapV3PoolUpperTickUpdated(pool, upperTickBound);
    }

    function setTWAPSecondsAgo(
        address pool,
        uint32  twapSecondsAgo,
        mapping (address => PoolParams) storage poolParams
    )
        external
    {
        // Required due to casting in UniswapV3OracleLibrary.consult
        // Limits twapSecondsAgo to approximately 68 years
        require(
            twapSecondsAgo < uint32(type(int32).max),
            "UniswapV3Lib/twap-seconds-ago-oob"
        );

        poolParams[pool].twapSecondsAgo = twapSecondsAgo;

        emit UniswapV3PoolTWAPSecondsAgoUpdated(pool, twapSecondsAgo);
    }

    /**********************************************************************************************/
    /*** Swap and liquidity management functions                                                ***/
    /**********************************************************************************************/

    function swap(
        address proxy,
        address rateLimits,
        address pool,
        address router,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta,
        mapping (address => PoolParams) storage poolParams
    )
        external
        returns (uint256 amountOut)
    {
        uint32 twapSecondsAgo = poolParams[pool].twapSecondsAgo;

        require(
            tickDelta <= poolParams[pool].swapMaxTickDelta,
            "UniswapV3Lib/invalid-max-tick-delta"
        );

        require(twapSecondsAgo != 0, "UniswapV3Lib/zero-twap-seconds");
        require(minAmountOut > 0,    "UniswapV3Lib/min-amount-not-set");

        ApproveLib.approve(tokenIn, proxy, router, amountIn);

        uint256 startingBalance = IERC20Like(tokenIn).balanceOf(proxy);

        amountOut = _callSwap({
            proxy          : proxy,
            pool           : pool,
            router         : router,
            tokenIn        : tokenIn,
            amountIn       : amountIn,
            minAmountOut   : minAmountOut,
            tickDelta      : tickDelta,
            twapSecondsAgo : twapSecondsAgo
        });

        uint256 amountSpent = startingBalance - IERC20Like(tokenIn).balanceOf(proxy);

        // Clear approvals of dust.
        ApproveLib.approve(tokenIn, proxy, router, 0);

        // Rate limit decreased by value of tokenIn (the amount actually spent).
        _decreaseRateLimit(rateLimits, LIMIT_SWAP, tokenIn, pool, amountSpent);
    }

    function addLiquidity(
        address             proxy,
        address             rateLimits,
        address             pool,
        address             positionManager,
        uint256             tokenId,
        Ticks        memory ticks,
        TokenAmounts memory target,
        TokenAmounts memory min,
        uint256             deadline,
        mapping (address => uint256)    storage maxSlippages,
        mapping (address => PoolParams) storage poolParams
    )
        external
        returns (uint256 tokenId_, uint128 liquidity_, TokenAmounts memory amounts_)
    {
        _validateAddLiquidityParameters(pool, ticks, target, min, maxSlippages, poolParams);

        ApproveLib.approve(
            IUniswapV3PoolLike(pool).token0(),
            proxy,
            positionManager,
            target.amount0
        );

        ApproveLib.approve(
            IUniswapV3PoolLike(pool).token1(),
            proxy,
            positionManager,
            target.amount1
        );

        if (tokenId == 0) {
            ( tokenId_, liquidity_, amounts_ ) = _mintLiquidity({
                proxy           : proxy,
                pool            : pool,
                positionManager : positionManager,
                ticks           : ticks,
                target          : target,
                min             : min,
                deadline        : deadline
            });
        } else {
            ( liquidity_, amounts_ ) = _increaseLiquidity({
                proxy           : proxy,
                pool            : pool,
                positionManager : positionManager,
                tokenId         : tokenId,
                ticks           : ticks,
                target          : target,
                min             : min,
                deadline        : deadline
            });

            tokenId_ = tokenId;
        }

        require(liquidity_ != 0, "UniswapV3Lib/no-liquidity-increased");

        // Clear approvals of dust.
        ApproveLib.approve(IUniswapV3PoolLike(pool).token0(), proxy, positionManager, 0);
        ApproveLib.approve(IUniswapV3PoolLike(pool).token1(), proxy, positionManager, 0);

        _decreaseRateLimit(
            rateLimits,
            LIMIT_DEPOSIT,
            IUniswapV3PoolLike(pool).token0(),
            pool,
            amounts_.amount0
        );

        _decreaseRateLimit(
            rateLimits,
            LIMIT_DEPOSIT,
            IUniswapV3PoolLike(pool).token1(),
            pool,
            amounts_.amount1
        );
    }

    function removeLiquidity(
        address             proxy,
        address             rateLimits,
        address             pool,
        address             positionManager,
        uint256             tokenId,
        uint128             liquidity,
        uint256             deadline,
        TokenAmounts memory min,
        mapping (address => uint256) storage maxSlippages
    )
        external
        returns (TokenAmounts memory amounts)
    {
        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        _validateRemoveLiquidityParams({
            proxy           : proxy,
            pool            : pool,
            positionManager : positionManager,
            tokenId         : tokenId,
            token0          : token0,
            token1          : token1,
            liquidity       : liquidity,
            maxSlippages    : maxSlippages
        });

        amounts = _callDecreaseLiquidity(proxy, positionManager, tokenId, liquidity, min, deadline);

        _callCollect(proxy, positionManager, tokenId);

        _checkSlippage(maxSlippages[pool], amounts.amount0, min.amount0);
        _checkSlippage(maxSlippages[pool], amounts.amount1, min.amount1);

        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, token0, pool, amounts.amount0);
        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, token1, pool, amounts.amount1);
    }

    /**********************************************************************************************/
    /*** Swap helper functions                                                                  ***/
    /**********************************************************************************************/

    function _callSwap(
        address proxy,
        address pool,
        address router,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta,
        uint32  twapSecondsAgo
    )
        internal
        returns (uint256 amountOut)
    {
        (
            address tokenOut,
            uint160 sqrtPriceLimitX96,
            uint24  fee
        ) = _getPoolData(pool, tokenIn, tickDelta, twapSecondsAgo);

        bytes memory callData = _getSwapCallData({
            proxy             : proxy,
            tokenIn           : tokenIn,
            tokenOut          : tokenOut,
            amountIn          : amountIn,
            minAmountOut      : minAmountOut,
            fee               : fee,
            sqrtPriceLimitX96 : sqrtPriceLimitX96
        });

        return abi.decode(IALMProxy(proxy).doCall(router, callData), (uint256));
    }

    function _getSwapCallData(
        address proxy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  fee,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(
            ISwapRouter.exactInputSingle,
            ISwapRouter.ExactInputSingleParams({
                tokenIn           : tokenIn,
                tokenOut          : tokenOut,
                fee               : fee,
                recipient         : proxy,
                amountIn          : amountIn,
                amountOutMinimum  : minAmountOut,
                sqrtPriceLimitX96 : sqrtPriceLimitX96
            })
        );
    }

    function _getPoolData(
        address pool,
        address tokenIn,
        uint24  tickDelta,
        uint32  twapSecondsAgo
    )
        internal
        view
        returns (address tokenOut, uint160 sqrtPriceLimitX96, uint24 fee)
    {
        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        require(
            tokenIn == token0 || tokenIn == token1,
            "UniswapV3Lib/invalid-token-pair"
        );

        tokenOut = tokenIn == token0 ? token1 : token0;

        // Fetch twap tick
        ( int24 twapTick, ) = UniswapV3OracleLib.consult(pool, twapSecondsAgo);

        int24 limitTick = (tokenIn == token0)
            ? _max(twapTick - int24(tickDelta), TickMath.MIN_TICK)
            : _min(twapTick + int24(tickDelta), TickMath.MAX_TICK);

        sqrtPriceLimitX96 = TickMath.getSqrtRatioAtTick(limitTick);

        fee = IUniswapV3PoolLike(pool).fee();
    }

    function _max(int24 a, int24 b) internal pure returns (int24) {
        return a > b ? a : b;
    }

    function _min(int24 a, int24 b) internal pure returns (int24) {
        return a < b ? a : b;
    }

    /**********************************************************************************************/
    /*** Add liquidity helper functions                                                         ***/
    /**********************************************************************************************/

    function _validateAddLiquidityParameters(
        address             pool,
        Ticks        memory ticks,
        TokenAmounts memory target,
        TokenAmounts memory min,
        mapping (address => uint256)    storage maxSlippages,
        mapping (address => PoolParams) storage poolParams
    )
        internal
        view
    {
        uint256 maxSlippage = maxSlippages[pool];

        require(target.amount0 > 0 || target.amount1 > 0, "UniswapV3Lib/zero-amount");
        require(maxSlippage != 0,                         "UniswapV3Lib/max-slippage-not-set");
        require(poolParams[pool].twapSecondsAgo != 0,     "UniswapV3Lib/zero-twap-seconds");

        // Check user input is within governance bounds.
        require(
            ticks.lower >= poolParams[pool].addLiquidityTickBounds.lower,
            "UniswapV3Lib/lower-tick-outside-bounds"
        );

        require(
            ticks.upper <= poolParams[pool].addLiquidityTickBounds.upper,
            "UniswapV3Lib/upper-tick-outside-bounds"
        );

        (
            uint256 expectedAmount0,
            uint256 expectedAmount1
        ) = _getExpectedAmounts(pool, ticks, target, poolParams[pool].twapSecondsAgo);

        _validateMinAmount(min.amount0, expectedAmount0, maxSlippage);
        _validateMinAmount(min.amount1, expectedAmount1, maxSlippage);
    }

    function _getExpectedAmounts(
        address             pool,
        Ticks        memory ticks,
        TokenAmounts memory target,
        uint32              twapSecondsAgo
    )
        internal
        view
        returns (uint256 expectedAmount0, uint256 expectedAmount1)
    {
        ( int24 twapTick, ) = UniswapV3OracleLib.consult(pool, twapSecondsAgo);

        uint160 sqrtTWAPPriceX96  = TickMath.getSqrtRatioAtTick(twapTick);
        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(ticks.lower);
        uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(ticks.upper);

        uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtTWAPPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96,
            target.amount0,
            target.amount1
        );

        if (twapTick <= ticks.lower) {
            expectedAmount0 = UniswapV3UtilsLib.getAmount0Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );
        } else if (twapTick >= ticks.upper) {
            expectedAmount1 = UniswapV3UtilsLib.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );
        } else {
            expectedAmount0 = UniswapV3UtilsLib.getAmount0Delta(
                sqrtTWAPPriceX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                false
            );

            expectedAmount1 = UniswapV3UtilsLib.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtTWAPPriceX96,
                expectedLiquidity,
                false
            );
        }
    }

    function _validateMinAmount(uint256 minAmount, uint256 expectedAmount, uint256 maxSlippage)
        internal
        pure
    {
        if (expectedAmount == 0) {
            require(minAmount == 0, "UniswapV3Lib/min-amount-below-bound");
            return;
        }

        uint256 minAmountThreshold = FullMath.mulDiv(expectedAmount, maxSlippage, 1e18);
        require(minAmount >= minAmountThreshold, "UniswapV3Lib/min-amount-below-bound");
    }

    function _mintLiquidity(
        address             proxy,
        address             pool,
        address             positionManager,
        Ticks        memory ticks,
        TokenAmounts memory target,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, TokenAmounts memory amounts)
    {
        int24 tickSpacing = IUniswapV3PoolLike(pool).tickSpacing();

        // Validate that lower and upper ticks are correctly spaced.
        require(ticks.lower % tickSpacing == 0, "UniswapV3Lib/invalid-lower-tick");
        require(ticks.upper % tickSpacing == 0, "UniswapV3Lib/invalid-upper-tick");

        return _callMintLiquidity(proxy, pool, positionManager, ticks, target, min, deadline);
    }

    function _callMintLiquidity(
        address             proxy,
        address             pool,
        address             positionManager,
        Ticks        memory ticks,
        TokenAmounts memory target,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, TokenAmounts memory amounts)
    {
        INonfungiblePositionManager.MintParams memory mintParams
            = INonfungiblePositionManager.MintParams({
                token0         : IUniswapV3PoolLike(pool).token0(),
                token1         : IUniswapV3PoolLike(pool).token1(),
                fee            : IUniswapV3PoolLike(pool).fee(),
                tickLower      : ticks.lower,
                tickUpper      : ticks.upper,
                recipient      : proxy,
                amount0Desired : target.amount0,
                amount1Desired : target.amount1,
                amount0Min     : min.amount0,
                amount1Min     : min.amount1,
                deadline       : deadline
            });

        bytes memory result = IALMProxy(proxy).doCall(
            positionManager,
            abi.encodeCall(INonfungiblePositionManager.mint, mintParams)
        );

        (
            tokenId,
            liquidity,
            amounts.amount0,
            amounts.amount1
        ) = abi.decode(result, (uint256, uint128, uint256, uint256));
    }

    function _increaseLiquidity(
        address             proxy,
        address             pool,
        address             positionManager,
        uint256             tokenId,
        Ticks        memory ticks,
        TokenAmounts memory target,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
        returns (uint128 liquidity, TokenAmounts memory amounts)
    {
        require(
            INonfungiblePositionManager(positionManager).ownerOf(tokenId) == proxy,
            "UniswapV3Lib/proxy-does-not-own-token-id"
        );

        (
            address token0,
            address token1,
            uint24  fee,
            int24   tickLower,
            int24   tickUpper,
            // ignore liquidity
        ) = _getPosition(tokenId, positionManager);

        require(
            IUniswapV3PoolLike(pool).token0() == token0 &&
            IUniswapV3PoolLike(pool).token1() == token1 &&
            IUniswapV3PoolLike(pool).fee() == fee,
            "UniswapV3Lib/invalid-pool"
        );

        require(tickLower == ticks.lower, "UniswapV3Lib/lower-tick-does-not-match-position");
        require(tickUpper == ticks.upper, "UniswapV3Lib/upper-tick-does-not-match-position");

        return _callIncreaseLiquidity(proxy, positionManager, tokenId, target, min, deadline);
    }

    function _callIncreaseLiquidity(
        address             proxy,
        address             positionManager,
        uint256             tokenId,
        TokenAmounts memory target,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
        returns (uint128 liquidity, TokenAmounts memory amounts)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams
            = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId        : tokenId,
                amount0Desired : target.amount0,
                amount1Desired : target.amount1,
                amount0Min     : min.amount0,
                amount1Min     : min.amount1,
                deadline       : deadline
            });

        bytes memory result = IALMProxy(proxy).doCall(
            positionManager,
            abi.encodeCall(
                INonfungiblePositionManager.increaseLiquidity,
                increaseLiquidityParams
            )
        );

        (
            liquidity,
            amounts.amount0,
            amounts.amount1
        ) = abi.decode(result, (uint128, uint256, uint256));
    }

    /**********************************************************************************************/
    /*** Remove liquidity helper functions                                                      ***/
    /**********************************************************************************************/

    function _validateRemoveLiquidityParams(
        address proxy,
        address pool,
        address positionManager,
        uint256 tokenId,
        address token0,
        address token1,
        uint128 liquidity,
        mapping (address => uint256) storage maxSlippages
    )
        internal
        view
    {
        require(maxSlippages[pool] != 0, "UniswapV3Lib/max-slippage-not-set");

        (
            address positionToken0,
            address positionToken1,
            uint24  positionFee,
            , // ignore tickLower
            , // ignore tickUpper
            uint128 positionLiquidity
        ) = _getPosition(tokenId, positionManager);

        require(
            positionToken0 == token0 &&
            positionToken1 == token1 &&
            positionFee == IUniswapV3PoolLike(pool).fee(),
            "UniswapV3Lib/invalid-pool"
        );

        require(liquidity != 0 && liquidity <= positionLiquidity, "UniswapV3Lib/liquidity-oob");

        require(
            INonfungiblePositionManager(positionManager).ownerOf(tokenId) == proxy,
            "UniswapV3Lib/proxy-does-not-own-token-id"
        );
    }

    function _callDecreaseLiquidity(
        address             proxy,
        address             positionManager,
        uint256             tokenId,
        uint128             liquidity,
        TokenAmounts memory min,
        uint256             deadline
    )
        internal
        returns (TokenAmounts memory amounts)
    {
        bytes memory result = IALMProxy(proxy).doCall(
            positionManager,
            abi.encodeCall(
                INonfungiblePositionManager.decreaseLiquidity,
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId    : tokenId,
                    liquidity  : liquidity,
                    amount0Min : min.amount0,
                    amount1Min : min.amount1,
                    deadline   : deadline
                })
            )
        );

        ( amounts.amount0, amounts.amount1 ) = abi.decode(result, (uint256, uint256));
    }

    function _callCollect(address proxy, address positionManager, uint256 tokenId)
        internal
        returns (TokenAmounts memory amounts)
    {
        bytes memory result = IALMProxy(proxy).doCall(
            positionManager,
            abi.encodeCall(
                INonfungiblePositionManager.collect,
                INonfungiblePositionManager.CollectParams({
                    tokenId    : tokenId,
                    recipient  : proxy,
                    amount0Max : type(uint128).max,
                    amount1Max : type(uint128).max
                })
            )
        );

        ( amounts.amount0, amounts.amount1 ) = abi.decode(result, (uint256, uint256));
    }

    function _checkSlippage(uint256 maxSlippage, uint256 amount, uint256 minAmount) internal pure {
        require(minAmount >= (amount * maxSlippage) / 1e18, "UniswapV3Lib/min-amount-below-bound");
    }

    /**********************************************************************************************/
    /*** General helper functions                                                               ***/
    /**********************************************************************************************/

    function _getPosition(uint256 tokenId, address positionManager) internal view returns (
        address token0,
        address token1,
        uint24  fee,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    ) {
        bytes memory positionData = abi.encodeCall(INonfungiblePositionManager.positions, tokenId);

        ( bool success, bytes memory result ) = positionManager.staticcall(positionData);

        require(success,              "UniswapV3Lib/positions-call-failed");
        require(result.length >= 384, "UniswapV3Lib/invalid-positions-return-data");

        assembly {
            // Pointer to the first return slot (nonce).
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

            // Sign-extend from int24 to int256 for proper handling.
            // If bit 23 is set (negative), extend with 1s, otherwise with 0s.
            // 2 = 24 bits - 1 byte (3 bytes total, 0-indexed = 2).
            tickLower := signextend(2, tickLower)
            tickUpper := signextend(2, tickUpper)
        }
    }

    function _decreaseRateLimit(
        address rateLimits,
        bytes32 key,
        address token,
        address pool,
        uint256 amount
    )
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(key, token, pool),
            amount
        );
    }

}
