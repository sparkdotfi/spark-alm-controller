// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { FullMath } from "../../../lib/dss-allocator/src/funnels/uniV3/FullMath.sol";
import { TickMath } from "../../../lib/dss-allocator/src/funnels/uniV3/TickMath.sol";

import {
    LiquidityAmounts
} from "../../../lib/dss-allocator/src/funnels/uniV3/LiquidityAmounts.sol";

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { UniswapV3Utils } from "./UniswapV3Utils.sol";

import { IUniswapV3Facet } from "./IUniswapV3Facet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

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

contract UniswapV3Facet is IUniswapV3Facet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.UniswapV3Facet.v1
    struct FacetStorage {
        mapping (address pool => uint256    maxSlippage) maxSlippages;  // 1e18 precision
        mapping (address pool => PoolParams params)      poolParams;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.UniswapV3Facet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xc41601344aaf9df41ecdea44841db009027b523fe5b6592e95408df889815700;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V3_DEPOSIT");
    bytes32 internal constant _LIMIT_SWAP     = keccak256("LIMIT_UNISWAP_V3_SWAP");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V3_WITHDRAW");

    // https://github.com/sky-ecosystem/dss-allocator/blob/a5469884/src/funnels/uniV3/TickMath.sol#L12-L15

    /// @inheritdoc IUniswapV3Facet
    uint24 public constant override MAX_TICK_DELTA = 887_272;

    /// @inheritdoc IUniswapV3Facet
    int24 public constant override MIN_TICK = -887_272;

    /// @inheritdoc IUniswapV3Facet
    int24 public constant override MAX_TICK = 887_272;

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV3Facet
    address public immutable override positionManager;

    /// @inheritdoc IUniswapV3Facet
    address public immutable override router;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address positionManager_, address router_) {
        require(positionManager_ != address(0), "UniswapV3Facet/zero-position-manager");
        require(router_          != address(0), "UniswapV3Facet/zero-router");

        positionManager = positionManager_;
        router          = router_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV3Facet
    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "UniswapV3Facet/pool-zero-address");

        emit UniswapV3MaxSlippageSet(pool, _getFacetStorage().maxSlippages[pool] = maxSlippage);
    }

    /// @inheritdoc IUniswapV3Facet
    function setMaxTickDelta(address pool, uint24 maxTickDelta)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "UniswapV3Facet/pool-zero-address");

        require(
            maxTickDelta > 0 && maxTickDelta <= MAX_TICK_DELTA,
            "UniswapV3Facet/max-tick-delta-oob"
        );

        _getFacetStorage().poolParams[pool].swapMaxTickDelta = maxTickDelta;

        emit UniswapV3MaxTickDeltaSet(pool, maxTickDelta);
    }

    /// @inheritdoc IUniswapV3Facet
    function setLiquidityLowerTickBound(address pool, int24 lowerTickBound)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "UniswapV3Facet/pool-zero-address");

        Ticks storage tickBounds = _getFacetStorage().poolParams[pool].liquidityTickBounds;

        require(
            lowerTickBound >= MIN_TICK && lowerTickBound < tickBounds.upper,
            "UniswapV3Facet/lower-tick-oob"
        );

        emit UniswapV3LowerTickSet(pool, tickBounds.lower = lowerTickBound);
    }

    /// @inheritdoc IUniswapV3Facet
    function setLiquidityUpperTickBound(address pool, int24 upperTickBound)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "UniswapV3Facet/pool-zero-address");

        Ticks storage tickBounds = _getFacetStorage().poolParams[pool].liquidityTickBounds;

        require(
            upperTickBound <= MAX_TICK && upperTickBound > tickBounds.lower,
            "UniswapV3Facet/upper-tick-oob"
        );

        emit UniswapV3UpperTickSet(pool, tickBounds.upper = upperTickBound);
    }

    /// @inheritdoc IUniswapV3Facet
    function setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "UniswapV3Facet/pool-zero-address");

        // Required due to casting in UniswapV3OracleLibrary.consult
        // Limits twapSecondsAgo to approximately 68 years
        require(twapSecondsAgo < uint32(type(int32).max), "UniswapV3Facet/twap-seconds-ago-oob");

        _getFacetStorage().poolParams[pool].twapSecondsAgo = twapSecondsAgo;

        emit UniswapV3TWAPSecondsAgoSet(pool, twapSecondsAgo);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV3Facet
    function swap(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 amountOut)
    {
        PoolParams storage poolParams = _getFacetStorage().poolParams[pool];

        require(tickDelta <= poolParams.swapMaxTickDelta, "UniswapV3Facet/invalid-max-tick-delta");
        require(poolParams.twapSecondsAgo != 0,           "UniswapV3Facet/zero-twap-seconds");
        require(minAmountOut > 0,                         "UniswapV3Facet/min-amount-not-set");

        _approve(tokenIn, router, amountIn);

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingBalance = IERC20Like(tokenIn).balanceOf(proxy);

        amountOut = _swap({
            pool         : pool,
            tokenIn      : tokenIn,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            tickDelta    : tickDelta
        });

        require(amountOut >= minAmountOut, "UniswapV3Facet/min-amount-out-not-met");

        uint256 amountSpent = startingBalance - IERC20Like(tokenIn).balanceOf(proxy);

        // Clear approvals of dust.
        _approve(tokenIn, router, 0);

        // Rate limit decreased by value of tokenIn (the amount actually spent).
        _decreaseRateLimit(getSwapRateLimitKey(pool, tokenIn), amountSpent);

        emit UniswapV3Swap(pool, tokenIn, amountSpent, amountOut);
    }

    /// @inheritdoc IUniswapV3Facet
    function addLiquidity(
        address               pool,
        uint256               tokenId,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 resultingTokenId, uint128 liquidity, TokenAmounts memory amounts)
    {
        _validateAddLiquidityParameters(pool, ticks, target, min);

        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        _approve(token0, positionManager, target.amount0);
        _approve(token1, positionManager, target.amount1);

        if (tokenId == 0) {
            ( resultingTokenId, liquidity, amounts ) = _mintLiquidity({
                pool     : pool,
                ticks    : ticks,
                target   : target,
                min      : min,
                deadline : deadline
            });
        } else {
            ( liquidity, amounts ) = _increaseLiquidity({
                pool     : pool,
                tokenId  : tokenId,
                ticks    : ticks,
                target   : target,
                min      : min,
                deadline : deadline
            });

            resultingTokenId = tokenId;
        }

        require(liquidity != 0, "UniswapV3Facet/no-liquidity-increased");

        // Clear approvals of dust.
        _approve(token0, positionManager, 0);
        _approve(token1, positionManager, 0);

        uint256 aggregateAmount =
            _toNormalizedAmount(token0, amounts.amount0) +
            _toNormalizedAmount(token1, amounts.amount1);

        // NOTE: The aggregate amount is used for aggregate deposit rate limit decrease, which makes
        //       the assumption that the tokens are valued equally
        //       (i.e. 1.000000 USDC = 1.000000000000000000 USDT). Aggregate rate limits should be
        //       set to "infinity" (`type(uint256).max`) for pools with tokens of different values.
        _decreaseRateLimit(getAggregateDepositRateLimitKey(pool),     aggregateAmount);
        _decreaseRateLimit(getAssetDepositRateLimitKey(pool, token0), amounts.amount0);
        _decreaseRateLimit(getAssetDepositRateLimitKey(pool, token1), amounts.amount1);

        emit UniswapV3AddLiquidity(
            pool,
            resultingTokenId,
            ticks.lower,
            ticks.upper,
            liquidity,
            amounts.amount0,
            amounts.amount1
        );
    }

    /// @inheritdoc IUniswapV3Facet
    function removeLiquidity(
        address               pool,
        uint256               tokenId,
        uint128               liquidity,
        TokenAmounts calldata min,
        uint256               deadline
    )
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (TokenAmounts memory amounts)
    {
        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        _validateRemoveLiquidityParams({
            pool      : pool,
            tokenId   : tokenId,
            token0    : token0,
            token1    : token1,
            liquidity : liquidity
        });

        _callCollect(tokenId); // Collect fees first.

        uint256 startingToken0Balance = _getProxyBalance(token0);
        uint256 startingToken1Balance = _getProxyBalance(token1);

        _callDecreaseLiquidity(tokenId, liquidity, min, deadline);

        _callCollect(tokenId);

        amounts.amount0 = _getProxyBalance(token0) - startingToken0Balance;
        amounts.amount1 = _getProxyBalance(token1) - startingToken1Balance;

        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        _checkSlippage(amounts.amount0, min.amount0, maxSlippage);
        _checkSlippage(amounts.amount1, min.amount1, maxSlippage);

        uint256 valueWithdrawn =
            _toNormalizedAmount(token0, amounts.amount0) +
            _toNormalizedAmount(token1, amounts.amount1);

        // NOTE: The aggregate amount is used for aggregate withdrawal rate limit decrease,
        //       which makes the assumption that the tokens are valued equally
        //       (i.e. 1.000000 USDC = 1.000000000000000000 USDT). Aggregate rate limits should be
        //       set to "infinity" (`type(uint256).max`) for pools with tokens of different values.
        _decreaseRateLimit(getAggregateWithdrawRateLimitKey(pool),     valueWithdrawn);
        _decreaseRateLimit(getAssetWithdrawRateLimitKey(pool, token0), amounts.amount0);
        _decreaseRateLimit(getAssetWithdrawRateLimitKey(pool, token1), amounts.amount1);

        emit UniswapV3RemoveLiquidity(pool, tokenId, liquidity, amounts.amount0, amounts.amount1);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV3Facet
    function getAggregateDepositRateLimitKey(address pool) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_DEPOSIT, pool);
    }

    /// @inheritdoc IUniswapV3Facet
    function getAssetDepositRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_DEPOSIT, token, pool);
    }

    /// @inheritdoc IUniswapV3Facet
    function getLiquidityTickBounds(address pool)
        external
        view
        override
        returns (int24 lower, int24 upper)
    {
        Ticks storage tickBounds = _getFacetStorage().poolParams[pool].liquidityTickBounds;

        return (tickBounds.lower, tickBounds.upper);
    }

    /// @inheritdoc IUniswapV3Facet
    function getMaxSlippage(address pool) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[pool];
    }

    /// @inheritdoc IUniswapV3Facet
    function getMaxTickDelta(address pool) external view override returns (uint24) {
        return _getFacetStorage().poolParams[pool].swapMaxTickDelta;
    }

    /// @inheritdoc IUniswapV3Facet
    function getSwapRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_SWAP, token, pool);
    }

    /// @inheritdoc IUniswapV3Facet
    function getTWAPSecondsAgo(address pool) external view override returns (uint32) {
        return _getFacetStorage().poolParams[pool].twapSecondsAgo;
    }

    /// @inheritdoc IUniswapV3Facet
    function getAggregateWithdrawRateLimitKey(address pool)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressKey(_LIMIT_WITHDRAW, pool);
    }

    /// @inheritdoc IUniswapV3Facet
    function getAssetWithdrawRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_WITHDRAW, token, pool);
    }

    /**********************************************************************************************/
    /*** Swap Helper Functions                                                                  ***/
    /**********************************************************************************************/

    function _swap(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        internal
        returns (uint256 amountOut)
    {
        (
            address tokenOut,
            uint160 sqrtPriceLimitX96,
            uint24  fee
        ) = _getPoolData(pool, tokenIn, tickDelta);

        bytes memory callData = _getSwapCallData({
            tokenIn           : tokenIn,
            tokenOut          : tokenOut,
            amountIn          : amountIn,
            minAmountOut      : minAmountOut,
            fee               : fee,
            sqrtPriceLimitX96 : sqrtPriceLimitX96
        });

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingBalance = IERC20Like(tokenOut).balanceOf(proxy);

        IALMProxy(proxy).doCall(router, callData);

        return IERC20Like(tokenOut).balanceOf(proxy) - startingBalance;
    }

    function _getSwapCallData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  fee,
        uint160 sqrtPriceLimitX96
    ) internal view returns (bytes memory) {
        return abi.encodeCall(
            ISwapRouter.exactInputSingle,
            ISwapRouter.ExactInputSingleParams({
                tokenIn           : tokenIn,
                tokenOut          : tokenOut,
                fee               : fee,
                recipient         : _getSharedControllerStorage().proxy,
                amountIn          : amountIn,
                amountOutMinimum  : minAmountOut,
                sqrtPriceLimitX96 : sqrtPriceLimitX96
            })
        );
    }

    function _getPoolData(address pool, address tokenIn, uint24 tickDelta)
        internal
        view
        returns (address tokenOut, uint160 sqrtPriceLimitX96, uint24 fee)
    {
        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        require(tokenIn == token0 || tokenIn == token1, "UniswapV3Facet/invalid-token-pair");

        tokenOut = tokenIn == token0 ? token1 : token0;

        // Fetch twap tick.
        (
            int24 twapTick, // arithmeticMeanTick
            // ignore harmonicMeanLiquidity
        ) = UniswapV3Utils.consult(pool, _getFacetStorage().poolParams[pool].twapSecondsAgo);

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
    /*** Add Liquidity Helper Functions                                                         ***/
    /**********************************************************************************************/

    function _validateAddLiquidityParameters(
        address               pool,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min
    )
        internal
        view
    {
        FacetStorage storage $          = _getFacetStorage();
        PoolParams   storage poolParams = $.poolParams[pool];
        Ticks        storage tickBounds = poolParams.liquidityTickBounds;

        uint256 maxSlippage = $.maxSlippages[pool];

        require(target.amount0 > 0 || target.amount1 > 0, "UniswapV3Facet/zero-amount");
        require(maxSlippage != 0,                         "UniswapV3Facet/max-slippage-not-set");
        require(poolParams.twapSecondsAgo != 0,           "UniswapV3Facet/zero-twap-seconds");

        // Check user input is within governance bounds.
        require(ticks.lower >= tickBounds.lower, "UniswapV3Facet/lower-tick-outside-bounds");
        require(ticks.upper <= tickBounds.upper, "UniswapV3Facet/upper-tick-outside-bounds");

        ( uint256 amount0, uint256 amount1 ) = _getExpectedAmounts(pool, ticks, target);

        _validateMinAmount(min.amount0, amount0, maxSlippage);
        _validateMinAmount(min.amount1, amount1, maxSlippage);
    }

    function _getExpectedAmounts(address pool, Ticks calldata ticks, TokenAmounts calldata target)
        internal
        view
        returns (uint256 expectedAmount0, uint256 expectedAmount1)
    {
        // Fetch twap tick.
        (
            int24 twapTick, // arithmeticMeanTick
            // ignore harmonicMeanLiquidity
        ) = UniswapV3Utils.consult(pool, _getFacetStorage().poolParams[pool].twapSecondsAgo);

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

        if (twapTick < ticks.lower) {
            expectedAmount0 = UniswapV3Utils.getAmount0Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                true
            );
        } else if (twapTick >= ticks.upper) {
            expectedAmount1 = UniswapV3Utils.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                true
            );
        } else {
            expectedAmount0 = UniswapV3Utils.getAmount0Delta(
                sqrtTWAPPriceX96,
                sqrtRatioUpperX96,
                expectedLiquidity,
                true
            );

            expectedAmount1 = UniswapV3Utils.getAmount1Delta(
                sqrtRatioLowerX96,
                sqrtTWAPPriceX96,
                expectedLiquidity,
                true
            );
        }
    }

    function _validateMinAmount(uint256 minAmount, uint256 expectedAmount, uint256 maxSlippage)
        internal
        pure
    {
        if (expectedAmount == 0) {
            require(minAmount == 0, "UniswapV3Facet/min-amount-below-bound");
            return;
        }

        // NOTE: This is effectively the same as `_checkSlippage`.
        uint256 minAmountThreshold = FullMath.mulDiv(expectedAmount, maxSlippage, 1e18);

        require(minAmount >= minAmountThreshold, "UniswapV3Facet/min-amount-below-bound");
    }

    function _mintLiquidity(
        address               pool,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, TokenAmounts memory amounts)
    {
        int24 tickSpacing = IUniswapV3PoolLike(pool).tickSpacing();

        // Validate that lower and upper ticks are correctly spaced.
        require(ticks.lower % tickSpacing == 0, "UniswapV3Facet/invalid-lower-tick");
        require(ticks.upper % tickSpacing == 0, "UniswapV3Facet/invalid-upper-tick");

        return _callMintLiquidity(pool, ticks, target, min, deadline);
    }

    function _callMintLiquidity(
        address               pool,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, TokenAmounts memory amounts)
    {
        address proxy  = _getSharedControllerStorage().proxy;
        address token0 = IUniswapV3PoolLike(pool).token0();
        address token1 = IUniswapV3PoolLike(pool).token1();

        INonfungiblePositionManager.MintParams memory mintParams
            = INonfungiblePositionManager.MintParams({
                token0         : token0,
                token1         : token1,
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

        uint256 startingToken0Balance = _getProxyBalance(token0);
        uint256 startingToken1Balance = _getProxyBalance(token1);

        bytes memory result = IALMProxy(proxy).doCall(
            positionManager,
            abi.encodeCall(INonfungiblePositionManager.mint, mintParams)
        );

        ( tokenId, liquidity, , ) = abi.decode(result, (uint256, uint128, uint256, uint256));

        amounts.amount0 = startingToken0Balance - _getProxyBalance(token0);
        amounts.amount1 = startingToken1Balance - _getProxyBalance(token1);
    }

    function _increaseLiquidity(
        address               pool,
        uint256               tokenId,
        Ticks        calldata ticks,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        internal
        returns (uint128 liquidity, TokenAmounts memory amounts)
    {
        _validateTokenOwnership(tokenId);

        (
            address token0,
            address token1,
            uint24  fee,
            int24   tickLower,
            int24   tickUpper,
            // ignore liquidity
        ) = _getPosition(tokenId);

        require(
            IUniswapV3PoolLike(pool).token0() == token0 &&
            IUniswapV3PoolLike(pool).token1() == token1 &&
            IUniswapV3PoolLike(pool).fee() == fee,
            "UniswapV3Facet/invalid-pool"
        );

        require(tickLower == ticks.lower, "UniswapV3Facet/lower-tick-does-not-match-position");
        require(tickUpper == ticks.upper, "UniswapV3Facet/upper-tick-does-not-match-position");

        uint256 startingToken0Balance = _getProxyBalance(token0);
        uint256 startingToken1Balance = _getProxyBalance(token1);

        liquidity = _callIncreaseLiquidity(tokenId, target, min, deadline);

        amounts.amount0 = startingToken0Balance - _getProxyBalance(token0);
        amounts.amount1 = startingToken1Balance - _getProxyBalance(token1);
    }

    function _callIncreaseLiquidity(
        uint256               tokenId,
        TokenAmounts calldata target,
        TokenAmounts calldata min,
        uint256               deadline
    )
        internal
        returns (uint128 liquidity)
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

        bytes memory result = IALMProxy(_getSharedControllerStorage().proxy).doCall(
            positionManager,
            abi.encodeCall(
                INonfungiblePositionManager.increaseLiquidity,
                increaseLiquidityParams
            )
        );

        ( liquidity, , ) = abi.decode(result, (uint128, uint256, uint256));
    }

    /**********************************************************************************************/
    /*** Remove Liquidity Helper Functions                                                      ***/
    /**********************************************************************************************/

    function _validateRemoveLiquidityParams(
        address pool,
        uint256 tokenId,
        address token0,
        address token1,
        uint128 liquidity
    )
        internal
        view
    {
        require(_getFacetStorage().maxSlippages[pool] != 0, "UniswapV3Facet/max-slippage-not-set");

        (
            address positionToken0,
            address positionToken1,
            uint24  positionFee,
            , // ignore tickLower
            , // ignore tickUpper
            uint128 positionLiquidity
        ) = _getPosition(tokenId);

        require(
            positionToken0 == token0 &&
            positionToken1 == token1 &&
            positionFee == IUniswapV3PoolLike(pool).fee(),
            "UniswapV3Facet/invalid-pool"
        );

        require(liquidity != 0 && liquidity <= positionLiquidity, "UniswapV3Facet/liquidity-oob");

        _validateTokenOwnership(tokenId);
    }

    function _callDecreaseLiquidity(
        uint256               tokenId,
        uint128               liquidity,
        TokenAmounts calldata min,
        uint256               deadline
    )
        internal
    {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
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
    }

    function _callCollect(uint256 tokenId) internal {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
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
    }

    function _checkSlippage(uint256 amount, uint256 minAmount, uint256 maxSlippage) internal pure {
        // NOTE: This is effectively the same as `_validateMinAmount`.
        require(
            minAmount >= (amount * maxSlippage) / 1e18,
            "UniswapV3Facet/min-amount-below-bound"
        );
    }

    /**********************************************************************************************/
    /*** General Helper Functions                                                               ***/
    /**********************************************************************************************/

    function _approve(address token, address spender, uint256 amount) internal {
        ApproveLib.approve(token, _getSharedControllerStorage().proxy, spender, amount);
    }

    function _getPosition(uint256 tokenId) internal view returns (
        address token0,
        address token1,
        uint24  fee,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    ) {
        bytes memory positionData = abi.encodeCall(INonfungiblePositionManager.positions, tokenId);

        ( bool success, bytes memory result ) = positionManager.staticcall(positionData);

        require(success,              "UniswapV3Facet/positions-call-failed");
        require(result.length >= 384, "UniswapV3Facet/invalid-positions-return-data");

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

    function _getProxyBalance(address token) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(_getSharedControllerStorage().proxy);
    }

    function _toNormalizedAmount(address token, uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _validateTokenOwnership(uint256 tokenId) internal view {
        require(
            INonfungiblePositionManager(positionManager).ownerOf(tokenId) ==
            _getSharedControllerStorage().proxy,
            "UniswapV3Facet/proxy-does-not-own-token-id"
        );
    }

}
