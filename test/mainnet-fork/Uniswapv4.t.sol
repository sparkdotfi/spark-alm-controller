// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { console } from "../../lib/forge-std/src/console.sol";

import { IAccessControl }  from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Currency } from "../../lib/uniswap-v4-periphery/lib/v4-core/src/types/Currency.sol";
import { PoolId }   from "../../lib/uniswap-v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey }  from "../../lib/uniswap-v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { FullMath } from "../../lib/uniswap-v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { TickMath } from "../../lib/uniswap-v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { IV4Router }     from "../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";
import { Actions }       from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { SlippageCheck } from "../../lib/uniswap-v4-periphery/src/libraries/SlippageCheck.sol";

import { makeBytes32Key } from "../../src/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    // NOTE: Purposely not returning bool to avoid issues with non-conformant tokens.
    function approve(address spender, uint256 amount) external;

    function allowance(address owner, address spender) external view returns (uint256 allowance);

    function balanceOf(address owner) external view returns (uint256 balance);

    function decimals() external view returns (uint8 decimals);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);

}

interface IPositionManagerLike {

    function transferFrom(address from, address to, uint256 id) external;

    function getPoolAndPositionInfo(uint256 tokenId)
        external
        view
        returns (PoolKey memory poolKey, PositionInfo info);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function nextTokenId() external view returns (uint256 nextTokenId);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory poolKeys);

}

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}

interface IUniversalRouterLike {

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;

}

interface IV4QuoterLike {

    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool    zeroForOne;
        uint128 exactAmount;
        bytes   hookData;
    }

    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

}

interface IV4RouterLike {

    error V4TooLittleReceived(uint256 minAmountOutReceived, uint256 amountReceived);

}

abstract contract UniswapV4_TestBase is ForkTestBase {

    struct IncreasePositionResult {
        uint256 tokenId;
        uint256 amount0Spent;
        uint256 amount1Spent;
        uint128 liquidityIncrease;
        int24   tickLower;
        int24   tickUpper;
    }

    struct DecreasePositionResult {
        uint256 tokenId;
        uint256 amount0Received;
        uint256 amount1Received;
        uint128 liquidityDecrease;
        int24   tickLower;
        int24   tickUpper;
    }

    uint256 internal constant _V4_SWAP = 0x10;

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");
    bytes32 internal constant _LIMIT_SWAP     = keccak256("LIMIT_UNISWAP_V4_SWAP");

    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address internal constant _STATE_VIEW       = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;
    address internal constant _V4_QUOTER        = 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;

    address internal immutable _unauthorized = makeAddr("unauthorized");
    address internal immutable _user         = makeAddr("user");

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setupLiquidity(bytes32 poolId, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        returns (IncreasePositionResult memory minted)
    {
        bytes32 depositLimitKey = makeBytes32Key(_LIMIT_DEPOSIT,  poolId);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(poolId, tickLower, tickUpper, uint24(uint256(int256(tickUpper) - int256(tickLower))));
        rateLimits.setRateLimitData(depositLimitKey, 200_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(poolId, tickLower, tickUpper, liquidity, 0.9999e18);

        minted = _mintPosition(poolId, tickLower, tickUpper, liquidity, amount0Max, amount1Max);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(poolId, 0, 0, 0);
        rateLimits.setRateLimitData(depositLimitKey, 0, 0);
        vm.stopPrank();
    }

    function _getIncreasePositionMaxAmounts(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint256 maxSlippage
    )
        internal
        view
        returns (uint128 amount0Max, uint128 amount1Max)
    {
        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            poolId,
            tickLower,
            tickUpper,
            liquidity
        );

        amount0Max = uint128((uint256(amount0Forecasted) * 1e18) / maxSlippage);
        amount1Max = uint128((uint256(amount1Forecasted) * 1e18) / maxSlippage);
    }

    function _mintPosition(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        internal
        returns (IncreasePositionResult memory result)
    {
        PoolKey memory poolKey = IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));

        deal(
            Currency.unwrap(poolKey.currency0),
            address(almProxy),
            _getBalanceOf(poolKey.currency0, address(almProxy)) + amount0Max
        );

        deal(
            Currency.unwrap(poolKey.currency1),
            address(almProxy),
            _getBalanceOf(poolKey.currency1, address(almProxy)) + amount1Max
        );

        uint256 token0BeforeCall    = _getBalanceOf(poolKey.currency0, address(almProxy));
        uint256 token1BeforeCall    = _getBalanceOf(poolKey.currency1, address(almProxy));
        bytes32 depositLimitKey     = makeBytes32Key(_LIMIT_DEPOSIT,  poolId);
        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(depositLimitKey);

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4(poolId, tickLower, tickUpper, liquidity, amount0Max, amount1Max);

        result.tokenId           = IPositionManagerLike(_POSITION_MANAGER).nextTokenId() - 1;
        result.amount0Spent      = token0BeforeCall - _getBalanceOf(poolKey.currency0, address(almProxy));
        result.amount1Spent      = token1BeforeCall - _getBalanceOf(poolKey.currency1, address(almProxy));
        result.liquidityIncrease = liquidity;
        result.tickLower         = tickLower;
        result.tickUpper         = tickUpper;

        assertLe(result.amount0Spent, amount0Max);
        assertLe(result.amount1Spent, amount1Max);

        assertEq(
            rateLimitBeforeCall - rateLimits.getCurrentRateLimit(depositLimitKey),
            _toNormalizedAmount(poolKey.currency0, result.amount0Spent) +
            _toNormalizedAmount(poolKey.currency1, result.amount1Spent)
        );

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(result.tokenId), result.liquidityIncrease);

        _assertZeroAllowances(Currency.unwrap(poolKey.currency0));
        _assertZeroAllowances(Currency.unwrap(poolKey.currency1));
    }

    function _increasePosition(
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        internal
        returns (IncreasePositionResult memory result)
    {
        (
            PoolKey memory poolKey,
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        bytes32 poolId = keccak256(abi.encode(poolKey));

        deal(
            Currency.unwrap(poolKey.currency0),
            address(almProxy),
            _getBalanceOf(poolKey.currency0, address(almProxy)) + amount0Max
        );

        deal(
            Currency.unwrap(poolKey.currency1),
            address(almProxy),
            _getBalanceOf(poolKey.currency1, address(almProxy)) + amount1Max
        );

        uint256 token0BeforeCall    = _getBalanceOf(poolKey.currency0, address(almProxy));
        uint256 token1BeforeCall    = _getBalanceOf(poolKey.currency1, address(almProxy));
        bytes32 depositLimitKey     = makeBytes32Key(_LIMIT_DEPOSIT, poolId);
        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(depositLimitKey);

        uint256 positionLiquidityBeforeCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4(poolId, tokenId, liquidityIncrease, amount0Max, amount1Max);

        result.tokenId           = tokenId;
        result.amount0Spent      = token0BeforeCall - _getBalanceOf(poolKey.currency0, address(almProxy));
        result.amount1Spent      = token1BeforeCall - _getBalanceOf(poolKey.currency1, address(almProxy));
        result.liquidityIncrease = liquidityIncrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();

        assertLe(result.amount0Spent, amount0Max);
        assertLe(result.amount1Spent, amount1Max);

        assertEq(
            rateLimitBeforeCall - rateLimits.getCurrentRateLimit(depositLimitKey),
            _toNormalizedAmount(poolKey.currency0, result.amount0Spent) +
            _toNormalizedAmount(poolKey.currency1, result.amount1Spent)
        );

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId),
            positionLiquidityBeforeCall + result.liquidityIncrease
        );

        _assertZeroAllowances(Currency.unwrap(poolKey.currency0));
        _assertZeroAllowances(Currency.unwrap(poolKey.currency1));
    }

    function _getDecreasePositionMinAmounts(uint256 tokenId, uint128 liquidity, uint256 maxSlippage)
        internal
        view
        returns (uint128 amount0Min, uint128 amount1Min)
    {
        (
            PoolKey memory poolKey,
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            keccak256(abi.encode(poolKey)),
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidity
        );

        amount0Min = uint128((uint256(amount0Forecasted) * maxSlippage) / 1e18);
        amount1Min = uint128((uint256(amount1Forecasted) * maxSlippage) / 1e18);
    }

    function _decreasePosition(
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        internal
        returns (DecreasePositionResult memory result)
    {
        (
            PoolKey memory poolKey,
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        bytes32 poolId = keccak256(abi.encode(poolKey));

        uint256 token0BeforeCall    = _getBalanceOf(poolKey.currency0, address(almProxy));
        uint256 token1BeforeCall    = _getBalanceOf(poolKey.currency1, address(almProxy));
        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(makeBytes32Key(_LIMIT_WITHDRAW, poolId));

        uint256 positionLiquidityBeforeCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4(poolId, tokenId, liquidityDecrease, amount0Min, amount1Min);

        result.tokenId           = tokenId;
        result.amount0Received   = _getBalanceOf(poolKey.currency0, address(almProxy)) - token0BeforeCall;
        result.amount1Received   = _getBalanceOf(poolKey.currency1, address(almProxy)) - token1BeforeCall;
        result.liquidityDecrease = liquidityDecrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();

        assertGe(result.amount0Received, amount0Min);
        assertGe(result.amount1Received, amount1Min);

        assertEq(
            rateLimitBeforeCall - rateLimits.getCurrentRateLimit(makeBytes32Key(_LIMIT_WITHDRAW, poolId)),
            _toNormalizedAmount(poolKey.currency0, result.amount0Received) +
            _toNormalizedAmount(poolKey.currency1, result.amount1Received)
        );

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId),
            positionLiquidityBeforeCall - result.liquidityDecrease
        );
    }

    function _getSwapAmountOutMin(
        bytes32 poolId,
        address tokenIn,
        uint128 amountIn,
        uint256 maxSlippage
    )
        internal
        returns (uint128 amountOutMin)
    {
        PoolKey memory poolKey = IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));

        address token0 = Currency.unwrap(poolKey.currency0);
        address token1 = Currency.unwrap(poolKey.currency1);

        IV4QuoterLike.QuoteExactSingleParams memory params = IV4QuoterLike.QuoteExactSingleParams({
            poolKey     : poolKey,
            zeroForOne  : tokenIn == token0,
            exactAmount : amountIn,
            hookData    : bytes("")
        });

        ( uint256 amountOut, ) = IV4QuoterLike(_V4_QUOTER).quoteExactInputSingle(params);

        return uint128((amountOut * maxSlippage) / 1e18);
    }

    function _swap(bytes32 poolId, address tokenIn, uint128 amountIn, uint128 amountOutMin)
        internal
        returns (uint256 amountOut)
    {
        Currency currencyIn  = Currency.wrap(tokenIn);
        Currency currencyOut = _getCurrencyOut(poolId, tokenIn);

        deal(
            Currency.unwrap(currencyIn),
            address(almProxy), _getBalanceOf(currencyIn, address(almProxy)) + amountIn
        );

        uint256 tokenInBeforeCall   = _getBalanceOf(currencyIn, address(almProxy));
        uint256 tokenOutBeforeCall  = _getBalanceOf(currencyOut, address(almProxy));
        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(makeBytes32Key(_LIMIT_SWAP, poolId));

        vm.prank(relayer);
        mainnetController.swapUniswapV4(poolId, tokenIn, amountIn, amountOutMin);

        amountOut = _getBalanceOf(currencyOut, address(almProxy)) - tokenOutBeforeCall;

        assertEq(tokenInBeforeCall - _getBalanceOf(currencyIn, address(almProxy)), amountIn);

        assertGe(amountOut, amountOutMin);

        assertEq(
            rateLimitBeforeCall - rateLimits.getCurrentRateLimit(makeBytes32Key(_LIMIT_SWAP, poolId)),
            _toNormalizedAmount(currencyIn, amountIn)
        );

        _assertZeroAllowances(Currency.unwrap(currencyIn));
        _assertZeroAllowances(Currency.unwrap(currencyOut));
    }

    function _getAmount0ForLiquidity(
        uint256 sqrtPriceAX96,
        uint256 sqrtPriceBX96,
        uint256 liquidity
    )
        internal
        pure
        returns (uint256 amount0)
    {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices-0");

        return FullMath.mulDiv(
            liquidity << 96,
            sqrtPriceBX96 - sqrtPriceAX96,
            sqrtPriceBX96 * sqrtPriceAX96
        );
    }

    function _getAmount1ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    )
        internal
        pure
        returns (uint256 amount1)
    {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices-1");

        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, 1 << 96);
    }

    function _getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    )
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices");

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            return (
                _getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity),
                0
            );
        }

        if (sqrtPriceX96 >= sqrtPriceBX96) {
            return (
                0,
                _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity)
            );
        }

        return (
            _getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity),
            _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity)
        );
    }

    function _getPrice(uint256 sqrtPriceX96) internal pure returns (uint256 price) {
        uint256 priceRoot = (sqrtPriceX96 * 1e18) >> 96;

        return (priceRoot * priceRoot) / 1e18;
    }

    function _getPrice(int24 tick) internal pure returns (uint256 price) {
        return _getPrice(TickMath.getSqrtPriceAtTick(tick));
    }

    function _getCurrentTick(bytes32 poolId) internal view returns (int24 tick) {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(poolId));

        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function _logCurrentPriceAndTick(bytes32 poolId) internal view {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(poolId));

        uint256 price = _getPrice(sqrtPriceX96);
        int24 tick    = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        if (price < 1e1) {
            console.log("price: 0.00000000000000000%s", price);
        } else if (price < 1e2) {
            console.log("price: 0.0000000000000000%s", price);
        } else if (price < 1e3) {
            console.log("price: 0.000000000000000%s", price);
        } else if (price < 1e4) {
            console.log("price: 0.00000000000000%s", price);
        } else if (price < 1e5) {
            console.log("price: 0.0000000000000%s", price);
        } else if (price < 1e6) {
            console.log("price: 0.000000000000%s", price);
        } else if (price < 1e7) {
            console.log("price: 0.00000000000%s", price);
        } else if (price < 1e8) {
            console.log("price: 0.0000000000%s", price);
        } else if (price < 1e9) {
            console.log("price: 0.000000000%s", price);
        } else if (price < 1e10) {
            console.log("price: 0.00000000%s", price);
        } else if (price < 1e11) {
            console.log("price: 0.0000000%s", price);
        } else if (price < 1e12) {
            console.log("price: 0.000000%s", price);
        } else if (price < 1e13) {
            console.log("price: 0.00000%s", price);
        } else if (price < 1e14) {
            console.log("price: 0.0000%s", price);
        } else if (price < 1e15) {
            console.log("price: 0.000%s", price);
        } else if (price < 1e16) {
            console.log("price: 0.00%s", price);
        } else if (price < 1e17) {
            console.log("price: 0.0%s", price);
        } else {
            uint256 quotient = price / 1e18;
            uint256 remainder = price % 1e18;

            if (remainder < 1e1) {
                console.log("price: %s.00000000000000000%s", quotient, remainder);
            } else if (remainder < 1e2) {
                console.log("price: %s.0000000000000000%s", quotient, remainder);
            } else if (remainder < 1e3) {
                console.log("price: %s.000000000000000%s", quotient, remainder);
            } else if (remainder < 1e4) {
                console.log("price: %s.00000000000000%s", quotient, remainder);
            } else if (remainder < 1e5) {
                console.log("price: %s.0000000000000%s", quotient, remainder);
            } else if (remainder < 1e6) {
                console.log("price: %s.000000000000%s", quotient, remainder);
            } else if (remainder < 1e7) {
                console.log("price: %s.00000000000%s", quotient, remainder);
            } else if (remainder < 1e8) {
                console.log("price: %s.0000000000%s", quotient, remainder);
            } else if (remainder < 1e9) {
                console.log("price: %s.000000000%s", quotient, remainder);
            } else if (remainder < 1e10) {
                console.log("price: %s.00000000%s", quotient, remainder);
            } else if (remainder < 1e11) {
                console.log("price: %s.0000000%s", quotient, remainder);
            } else if (remainder < 1e12) {
                console.log("price: %s.000000%s", quotient, remainder);
            } else if (remainder < 1e13) {
                console.log("price: %s.00000%s", quotient, remainder);
            } else if (remainder < 1e14) {
                console.log("price: %s.0000%s", quotient, remainder);
            } else if (remainder < 1e15) {
                console.log("price: %s.000%s", quotient, remainder);
            } else if (remainder < 1e16) {
                console.log("price: %s.00%s", quotient, remainder);
            } else if (remainder < 1e17) {
                console.log("price: %s.0%s", quotient, remainder);
            } else {
                console.log("price: %s.%s", quotient, remainder);
            }
        }

        console.log(" -> tick: %s", tick);
    }

    function _quoteLiquidity(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidityAmount
    )
        internal
        view
        returns (uint128 amount0, uint128 amount1)
    {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(poolId));

        ( uint256 amount0Raw, uint256 amount1Raw ) = _getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        return (uint128(amount0Raw), uint128(amount1Raw));
    }

    function _assertZeroAllowances(address token) internal view {
        ( uint160 allowance, , ) = IPermit2Like(_PERMIT2).allowance(address(almProxy), token, _POSITION_MANAGER);

        assertEq(allowance, 0, "permit2 allowance not 0");

        assertEq(IERC20Like(token).allowance(address(almProxy), _PERMIT2), 0, "allowance to permit2 not 0");
    }

    function _to18From6Decimals(uint256 amount) internal pure returns (uint256) {
        return amount * 1e12;
    }

    function _toNormalizedAmount(address token, uint256 amount)
        internal
        view
        returns (uint256 normalizedAmount)
    {
        return amount * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _toNormalizedAmount(Currency currency, uint256 amount)
        internal
        view
        returns (uint256 normalizedAmount)
    {
        return amount * 1e18 / (10 ** IERC20Like(Currency.unwrap(currency)).decimals());
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23470490;  // September 29, 2025
    }

    function _externalSwap(bytes32 poolId, address account, address tokenIn, uint128 amountIn)
        internal
        returns (uint256 amountOut)
    {
        PoolKey memory poolKey = IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));

        address token0   = Currency.unwrap(poolKey.currency0);
        address token1   = Currency.unwrap(poolKey.currency1);
        address tokenOut = tokenIn == token0 ? token1 : token0;

        deal(tokenIn, account, amountIn);

        bytes memory commands = abi.encodePacked(uint8(_V4_SWAP));

        bytes[] memory inputs = new bytes[](1);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey          : poolKey,
                zeroForOne       : tokenIn == token0,
                amountIn         : amountIn,
                amountOutMinimum : 0,
                hookData         : bytes("")
            })
        );

        params[1] = abi.encode(tokenIn,  amountIn);
        params[2] = abi.encode(tokenOut, 0);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        uint256 startingOutBalance = IERC20Like(tokenOut).balanceOf(account);

        // Execute the swap
        vm.startPrank(account);
        IERC20Like(tokenIn).approve(_PERMIT2, amountIn);
        IPermit2Like(_PERMIT2).approve(tokenIn, _ROUTER, amountIn, uint48(block.timestamp));
        IUniversalRouterLike(_ROUTER).execute(commands, inputs, block.timestamp);
        vm.stopPrank();

        return IERC20Like(tokenOut).balanceOf(account) - startingOutBalance;
    }

    function _getBalanceOf(Currency currency, address  account)
        internal
        view
        returns (uint256 balance)
    {
        return IERC20Like(Currency.unwrap(currency)).balanceOf(account);
    }

    function _getCurrencyOut(bytes32 poolId, address tokenIn)
        internal
        view
        returns (Currency currencyOut)
    {
        PoolKey memory poolKey = IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));

        return tokenIn == Currency.unwrap(poolKey.currency0) ? poolKey.currency1 : poolKey.currency0;
    }

}

contract MainnetController_UniswapV4_Tests is UniswapV4_TestBase {

    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.mintPositionUniswapV4({
            poolId     : bytes32(0),
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.mintPositionUniswapV4({
            poolId     : bytes32(0),
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    /**********************************************************************************************/
    /*** increaseLiquidity Tests                                                                ***/
    /**********************************************************************************************/

    function test_increaseLiquidityUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    /**********************************************************************************************/
    /*** decreaseLiquidityUniswapV4 Tests                                                       ***/
    /**********************************************************************************************/

    function test_decreaseLiquidityUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    /**********************************************************************************************/
    /*** swapUniswapV4 Tests                                                                   ***/
    /**********************************************************************************************/

    function test_swapUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUniswapV4(bytes32(0), address(0), 0, 0);
    }

    function test_swapUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.swapUniswapV4(bytes32(0), address(0), 0, 0);
    }

}

contract MainnetController_UniswapV4_USDC_USDT_Tests is UniswapV4_TestBase {

    // Uniswap V4 USDC/USDT pool
    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    bytes32 internal constant _DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(_LIMIT_DEPOSIT,  _POOL_ID));
    bytes32 internal constant _WITHDRAW_LIMIT_KEY = keccak256(abi.encode(_LIMIT_WITHDRAW, _POOL_ID));
    bytes32 internal constant _SWAP_LIMIT_KEY     = keccak256(abi.encode(_LIMIT_SWAP,     _POOL_ID));

    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_revertsWhenTickLimitsNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLimits-not-set");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTicksMisorderedBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -6,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -4,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickLowerTooLowBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLower-too-low");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -11,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickUpperTooHighBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickUpper-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 1,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickSpacingTooWideBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 10, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickSpacing-too-wide");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 6,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenMaxAmountsSurpassedBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdc), address(almProxy), amount0Forecasted);
        deal(address(usdt), address(almProxy), amount1Forecasted);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted - 1, amount0Forecasted)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted - 1,
            amount1Max : amount1Forecasted
        });

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted - 1, amount1Forecasted)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted - 1
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });
    }

    function test_mintPositionUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        uint256 expectedDecrease = 499.966111e18;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdc), address(almProxy), amount0Forecasted);
        deal(address(usdt), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });
    }

    function test_mintPositionUniswapV4() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(_POOL_ID, -10, 0, 1_000_000e6, 0.99e18);

        vm.record();

        IncreasePositionResult memory result = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 340.756158e6);
        assertEq(result.amount1Spent, 159.209953e6);
    }

    /**********************************************************************************************/
    /*** increaseLiquidity Tests                                                                ***/
    /**********************************************************************************************/

    function test_increaseLiquidityUniswapV4_revertsWhenPositionIsNotOwnedByProxy() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(address(almProxy));
        IPositionManagerLike(_POSITION_MANAGER).transferFrom(address(almProxy), address(1), minted.tokenId);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/non-proxy-position");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/poolKey-poolId-mismatch");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickLowerTooLowBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -9, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLower-too-low");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickUpperTooHighBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, -1, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickUpper-too-high");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickSpacingTooWideBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 9);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickSpacing-too-wide");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : 1_000_000e6,
            amount1Max        : 1_000_000e6
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenMaxAmountsSurpassedBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdc), address(almProxy), amount0Forecasted);
        deal(address(usdt), address(almProxy), amount1Forecasted);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted - 1, amount0Forecasted)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted - 1,
            amount1Max        : amount1Forecasted
        });

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted - 1, amount1Forecasted)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted - 1
        });

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        uint256 expectedDecrease = 499.966111e18;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdc), address(almProxy), amount0Forecasted);
        deal(address(usdt), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6,
            0.99e18
        );

        vm.record();

        IncreasePositionResult memory result = _increasePosition(
            minted.tokenId,
            1_000_000e6,
            amount0Max,
            amount1Max
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 340.756158e6);
        assertEq(result.amount1Spent, 159.209953e6);
    }

    /**********************************************************************************************/
    /*** decreaseLiquidityUniswapV4 Tests                                                       ***/
    /**********************************************************************************************/

    function test_decreaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/poolKey-poolId-mismatch");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount0MinNotMetBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount0Forecasted + 1,
                amount0Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted + 1,
            amount1Min        : amount1Forecasted
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount1MinNotMetBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount1Forecasted + 1,
                amount1Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted + 1
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        uint256 expectedDecrease = 249.983054e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease - 1, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_partial() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Min, uint128 amount1Min ) = _getDecreasePositionMinAmounts(
            minted.tokenId,
            minted.liquidityIncrease / 2,
            0.99e18
        );

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(
            minted.tokenId,
            minted.liquidityIncrease / 2,
            amount0Min,
            amount1Min
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 170.378078e6);
        assertEq(result.amount1Received, 79.604976e6);
    }

    function test_decreaseLiquidityUniswapV4_all() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, -10, 0, 1_000_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Min, uint128 amount1Min ) = _getDecreasePositionMinAmounts(
            minted.tokenId,
            minted.liquidityIncrease,
            0.99e18
        );

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(
            minted.tokenId,
            minted.liquidityIncrease,
            amount0Min,
            amount1Min
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 340.756157e6);
        assertEq(result.amount1Received, 159.209952e6);
    }

    /**********************************************************************************************/
    /*** swapUniswapV4 Tests                                                                    ***/
    /**********************************************************************************************/

    function test_swapUniswapV4_revertsWhenMaxSlippageNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/max-slippage-not-set");
        mainnetController.swapUniswapV4(_POOL_ID, address(0), 0, 0);
    }

    function test_swapUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 1_000_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usdc), 1_000_000e6, 0.99e18);

        deal(address(usdc), address(almProxy), 1_000_000e6 + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUniswapV4({
            poolId       : _POOL_ID,
            tokenIn      : address(usdc),
            amountIn     : 1_000_000e6 + 1,
            amountOutMin : amountOutMin
        });

        vm.prank(relayer);
        mainnetController.swapUniswapV4({
            poolId       : _POOL_ID,
            tokenIn      : address(usdc),
            amountIn     : 1_000_000e6,
            amountOutMin : amountOutMin
        });
    }

    function test_swapUniswapV4_revertsWhenInputTokenNotForPool() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/invalid-tokenIn");
        mainnetController.swapUniswapV4(_POOL_ID, address(dai), 1_000_000e6, 1_000_000e6);
    }

    function test_swapUniswapV4_revertsWhenAmountOutMinTooLowBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/amountOutMin-too-low");
        mainnetController.swapUniswapV4(_POOL_ID, address(usdc), 1_000_000e6, 980_000e6 - 1);

        vm.prank(relayer);
        mainnetController.swapUniswapV4(_POOL_ID, address(usdc), 1_000_000e6, 980_000e6);
    }

    function test_swapUniswapV4_revertsWhenAmountOutMinNotMetBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                IV4RouterLike.V4TooLittleReceived.selector,
                999_280.652247e6 + 1,
                999_280.652247e6
            )
        );

        mainnetController.swapUniswapV4(_POOL_ID, address(usdc), 1_000_000e6, 999_280.652247e6 + 1);

        vm.prank(relayer);
        mainnetController.swapUniswapV4(_POOL_ID, address(usdc), 1_000_000e6, 999_280.652247e6);
    }

    function test_swapUniswapV4_token0toToken1() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usdc), 1_000_000e6, 0.99e18);

        vm.record();

        uint256 amountOut = _swap(_POOL_ID, address(usdc), 1_000_000e6, amountOutMin);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 999_280.652247e6);
    }

    function test_swapUniswapV4_token1toToken0() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usdt), 1_000_000e6, 0.99e18);

        vm.record();

        uint256 amountOut = _swap(_POOL_ID, address(usdt), 1_000_000e6, amountOutMin);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 1_000_646.141415e6);
    }

    /**********************************************************************************************/
    /*** Fuzz Tests                                                                             ***/
    /**********************************************************************************************/

    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_mintAndDecreaseFullAmounts(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    )
        external
    {
        tickLower = int24(_bound(int256(tickLower), -10_000, 10_000 - 1));

        int256 boundedUpperMax = int256(tickLower) + 1_000 > 10_000 ? int256(10_000) : int256(tickLower) + 1_000;

        tickUpper = int24(_bound(int256(tickUpper), int256(tickLower) + 1, boundedUpperMax));
        liquidity = uint128(_bound(uint256(liquidity), 1e6, 1_000_000_000e6));

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10_000, 10_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  1_000_000_000e18, uint256(1_000_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 1_000_000_000e18, uint256(1_000_000_000e18) / 1 days);
        vm.stopPrank();

        IncreasePositionResult memory mintResult     = _mintPosition(_POOL_ID, tickLower, tickUpper, liquidity, type(uint128).max, type(uint128).max);
        DecreasePositionResult memory decreaseResult = _decreasePosition(mintResult.tokenId, mintResult.liquidityIncrease, 0, 0);

        uint256 valueDeposited = mintResult.amount0Spent        + mintResult.amount1Spent;
        uint256 valueReceived  = decreaseResult.amount0Received + decreaseResult.amount1Received;

        assertApproxEqAbs(valueReceived, valueDeposited, 2);
    }

    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_increaseAndDecreaseFullAmounts(
        int24   tickLower,
        int24   tickUpper,
        uint128 initialLiquidity
    )
        external
    {
        tickLower = int24(_bound(int256(tickLower), -10_000, 10_000 - 1));

        int256 boundedUpperMax = int256(tickLower) + 1_000 > 10_000 ? int256(10_000) : int256(tickLower) + 1_000;

        tickUpper        = int24(_bound(int256(tickUpper), int256(tickLower) + 1, boundedUpperMax));
        initialLiquidity = uint128(_bound(uint256(initialLiquidity), 1e6, 2_000_000e6));

        uint128 additionalLiquidity = initialLiquidity / 2;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10_000, 10_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        IncreasePositionResult memory mintResult     = _mintPosition(_POOL_ID, tickLower, tickUpper, initialLiquidity, type(uint128).max, type(uint128).max);
        IncreasePositionResult memory increaseResult = _increasePosition(mintResult.tokenId, additionalLiquidity, type(uint128).max, type(uint128).max);

        uint256 valueBeforeIncrease = mintResult.amount0Spent     + mintResult.amount1Spent;
        uint256 valueAdded          = increaseResult.amount0Spent + increaseResult.amount1Spent;
        uint256 totalValueDeposited = valueBeforeIncrease + valueAdded;

        uint128 totalLiquidity = mintResult.liquidityIncrease + increaseResult.liquidityIncrease;

        DecreasePositionResult memory decreaseResult = _decreasePosition(mintResult.tokenId, totalLiquidity, 0, 0);

        uint256 valueReceived = decreaseResult.amount0Received + decreaseResult.amount1Received;

        assertApproxEqAbs(totalValueDeposited, valueReceived, 10);
    }

    /// @param swapDirection true = USDC->USDT, false = USDT->USDC
    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_swapUniswapV4_amounts(uint128 amountIn, bool swapDirection)
        external
    {
        amountIn = uint128(_bound(uint256(amountIn), 1e6, 1_000_000e6));

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 1_000_000e18, 0);
        vm.stopPrank();

        address tokenIn = swapDirection ? address(usdc) : address(usdt);

        uint128 amountOutMin    = _getSwapAmountOutMin(_POOL_ID, tokenIn, amountIn, 0.99e18);
        uint256 rateLimitBefore = rateLimits.getCurrentRateLimit(_SWAP_LIMIT_KEY);
        uint256 amountOut       = _swap(_POOL_ID, tokenIn, amountIn, amountOutMin);

        assertEq(rateLimits.getCurrentRateLimit(_SWAP_LIMIT_KEY), rateLimitBefore - _to18From6Decimals(amountIn));

        assertGe(amountOut, amountOutMin);

        assertApproxEqRel(amountIn, amountOut, 0.005e18);
    }

    /**********************************************************************************************/
    /*** Story Tests                                                                            ***/
    /**********************************************************************************************/

    /**
     * @dev Story 1 is a round trip of liquidity minting, increase, decreasing, and closing/burning,
     *      each 90 days apart, while an external account swaps tokens in and out of the pool.
     *      - The relayer mints a position with 4_000e12 liquidity.
     *      - The relayer increases the liquidity position by 50% (to 2_000e12 liquidity).
     *      - The relayer decreases the liquidity position by 50% (to 3_000e12 liquidity).
     *      - The relayer decreases the remaining liquidity position (to 0 liquidity).
     */
    function test_uniswapV4_story1() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        // 1. The relayer mints a position with 1,000,000 liquidity.
        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 4_000e12,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 1_363_024.631364e6);
        assertEq(increaseResult.amount1Spent, 636_839.809432e6);

        uint256 expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 2. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 3. Some account swaps 1,000,000 USDT for USDC.
        assertEq(_externalSwap(_POOL_ID, _user, address(usdt), 1_000_000e6), 1_000_648.496032e6);

        // 4. The relayer increases the liquidity position by 50%.
        increaseResult = _increasePosition(increaseResult.tokenId, 2_000e12, type(uint128).max, type(uint128).max);

        assertEq(increaseResult.amount0Spent, 635_276.445136e6);
        assertEq(increaseResult.amount1Spent, 364_624.424738e6);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 5. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 6. Some account swaps 1,500,000 USDC for USDT.
        assertEq(_externalSwap(_POOL_ID, _user, address(usdc), 1_500_000e6), 1_498_982.907513e6);

        // 7. The relayer decreases the liquidity position by 50%.
        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 3_000e12, 0, 0);

        assertEq(decreaseResult.amount0Received, 1_052_773.305651e6);
        assertEq(decreaseResult.amount1Received, 447_148.109354e6);

        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 8. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 9. Some account swaps 1,000,000 USDT for USDC.
        assertEq(_externalSwap(_POOL_ID, _user, address(usdt), 1_000_000e6), 1_000_667.948623e6);

        // 10. The relayer decreases the remaining liquidity position.
        decreaseResult = _decreasePosition(increaseResult.tokenId, 3_000e12, 0, 0);

        assertEq(decreaseResult.amount0Received, 981_255.571670e6);
        assertEq(decreaseResult.amount1Received, 518_616.097207e6);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(decreaseResult.tokenId),
            0
        );
    }

    /**********************************************************************************************/
    /*** Log Price And Ticks Tests                                                              ***/
    /**********************************************************************************************/

    function test_uniswapV4_logPriceAndTicks_increasingPrice() external {
        vm.skip(true);

        for (uint256 i = 0; i <= 100; ++i) {
            if (i != 0) {
                _externalSwap(_POOL_ID, _user, address(usdt), 200_000e6);
            }

            _logCurrentPriceAndTick(_POOL_ID);
            console.log(" -> After swapping: %s USDT\n", uint256(i * 200_000));
        }
    }

    function test_uniswapV4_logPriceAndTicks_decreasingPrice() external {
        vm.skip(true);

        for (uint256 i = 0; i <= 100; ++i) {
            if (i != 0) {
                _externalSwap(_POOL_ID, _user, address(usdc), 200_000e6);
            }

            _logCurrentPriceAndTick(_POOL_ID);
            console.log(" -> After swapping: %s USDC\n", uint256(i * 200_000));
        }
    }

    /**********************************************************************************************/
    /*** Attack Tests (Current price is expected to be between the range)                       ***/
    /**********************************************************************************************/

    function test_uniswapV4_baseline_priceMid() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be between the range)                  ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 840_606.192834e6);
        assertEq(increaseResult.amount1Spent, 159_209.952358e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_816.145192e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 840_606.192833e6);
        assertEq(decreaseResult.amount1Received, 159_209.952357e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_816.145190e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceMidToAbove() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdt), 19_200_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be between the range, but is above)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 11);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 0); // Expected 840_606.192834e6 as per baseline
        assertEq(increaseResult.amount1Spent, 999_950.044994e6); // Expected 159_209.952358e6 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_950.044994e6); // Expected 999_816.145192e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 11);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 19_200_305.050324e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 19_200_305.050324e6); // Gained 305 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 819_742.888121e6);
        assertEq(decreaseResult.amount1Received, 180_067.672764e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_810.560885e6); // Lost 139 USD from mint
    }

    function test_uniswapV4_attack_priceMidToBelow() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdc), 2_500_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be between the range, but is below)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -11);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 999_950.044994e6); // Expected 840_606.192834e6 as per baseline
        assertEq(increaseResult.amount1Spent, 0); // Expected 159_209.952358e6 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_950.044994e6); // Expected 999_816.145192e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -11);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_499_974.750232e6);
        assertEq(usdc.balanceOf(_user), 2_499_974.750232e6); // Lost 26 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 844_561.661143e6);
        assertEq(decreaseResult.amount1Received, 155_258.746587e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_820.40773e6); // Lost 129 USD from mint
    }

    /**********************************************************************************************/
    /*** Attack Tests (Current price is expected to be below the range)                         ***/
    /**********************************************************************************************/

    function test_uniswapV4_baseline_priceBelow() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be below the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 15,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 999_700.101224e6);
        assertEq(increaseResult.amount1Spent, 0);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_700.101224e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_700.101223e6);
        assertEq(decreaseResult.amount1Received, 0);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_700.101223e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceBelowToMid() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdt), 18_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be below the range, but is between)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 2);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 15,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 632_055.655046e6); // Expected 999_700.101224e6 as per baseline
        assertEq(increaseResult.amount1Spent, 367_595.789859e6); // Expected 0 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_651.444905e6); // Expected 999_700.101224e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 2);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 17_999_838.406844e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 17_999_838.406844e6); // Lost 161 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_703.777704e6);
        assertEq(decreaseResult.amount1Received, 0);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_703.777704e6); // Gained 52 USD from mint.
    }

    function test_uniswapV4_attack_priceBelowToAbove() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdt), 19_300_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be below the range, but is above)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 34);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 15,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 0); // Expected 999_700.101224e6 as per baseline
        assertEq(increaseResult.amount1Spent, 1_000_200.051255e6); // Expected 0 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 1_000_200.051255e6); // Expected 999_700.101224e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), 34);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 19_300_769.578693e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 19_300_769.578693e6); // Gained 769 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_710.098327e6);
        assertEq(decreaseResult.amount1Received, 0);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_710.098327e6); // Lost 490 USD from mint
    }

    /**********************************************************************************************/
    /*** Attack Tests (Current price is expected to be above the range)                         ***/
    /**********************************************************************************************/

    function test_uniswapV4_baseline_priceAbove() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be above the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -30,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 0);
        assertEq(increaseResult.amount1Spent, 998_950.644702e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 998_950.644702e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 998_950.644701e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_950.644701e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceAboveToMid() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdc), 2_840_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is between)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -20);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -30,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 457_787.249555e6); // Expected 0 as per baseline
        assertEq(increaseResult.amount1Spent, 541_830.090075e6); // Expected 998_950.644702e6 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_617.339630e6); // Expected 998_950.644702e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -20);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_840_292.929030e6);
        assertEq(usdc.balanceOf(_user), 2_840_292.929030e6); // Gained 292 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -8);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 998_955.215954e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_955.215954e6); // Lost 662 USD from mint
    }

    function test_uniswapV4_attack_priceAboveToBelow() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdc), 2_900_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -50);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -30,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 1_000_950.445137e6); // Expected 0 as per baseline
        assertEq(increaseResult.amount1Spent, 0); // Expected 998_950.644702e6 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 1_000_950.445137e6); // Expected 998_950.644702e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -50);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_901_232.701533e6);
        assertEq(usdc.balanceOf(_user), 2_901_232.701533e6); // Gained 1_232 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -8);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 998_960.634310e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_960.634310e6); // Lost 1,989 USD from mint
    }

    function test_uniswapV4_attack_priceAboveToBelow_defended() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Get max amounts                                                                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        // While recommended usage is to use max amounts that are exactly (or close to exactly) the
        // forecasted amounts in production, however this shows that even a value of 0.99 is
        // sufficient to prevent an attack.
        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(_POOL_ID, -30, -10, 1_000_000_000e6, 0.99e18);

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        _externalSwap(_POOL_ID, _user, address(usdc), 2_900_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -50);

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Max);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Max);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, 0, 1_000_950.445137e6)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -30,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });
    }

    /**********************************************************************************************/
    /*** Attack Tests (Current price is expected to be above the range, with wide tick spacing) ***/
    /**********************************************************************************************/

    function test_uniswapV4_baseline_priceAbove_wideTicks() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 200); // Allow wider tick range.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be above the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -200,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 0);
        assertEq(increaseResult.amount1Spent, 9_449_821.223798e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 9_449_821.223798e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 9_449_821.223797e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 9_449_821.223797e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceAboveToBelow_wideTicks() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 200); // Allow wider tick spacing.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        uint256 amountOut1 = _externalSwap(_POOL_ID, _user, address(usdc), 3_020_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -501);

        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : -200,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 9_549_562.082877e6); // Expected 0 as per baseline
        assertEq(increaseResult.amount1Spent, 0); // Expected 9_449_821.223798e6 as per baseline
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 9_549_562.082877e6); // Expected 9_449_821.223798e6 as per baseline

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -501);

        uint256 amountOut2 = _externalSwap(_POOL_ID, _user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 3_067_685.526025e6);
        assertEq(usdc.balanceOf(_user), 3_067_685.526025e6); // Gained 47_685 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -141);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 6_528_153.154390e6);
        assertEq(decreaseResult.amount1Received, 2_970_499.394905e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 9_498_652.549295e6); // Lost 50,909 USD from mint
    }

    function test_uniswapV4_attack_priceAboveToBelow_defended_wideTicks() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20); // Disallow wider tick spacing.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -7);

        _externalSwap(_POOL_ID, _user, address(usdc), 3_020_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(_POOL_ID), -501);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickSpacing-too-wide");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -200,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });
    }

}

contract MainnetController_UniswapV4_USDT_USDS_Tests is UniswapV4_TestBase {

    bytes32 internal constant _POOL_ID = 0xb54ece65cc2ddd3eaec0ad18657470fb043097220273d87368a062c7d4e59180;

    bytes32 internal constant _DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(_LIMIT_DEPOSIT,  _POOL_ID));
    bytes32 internal constant _WITHDRAW_LIMIT_KEY = keccak256(abi.encode(_LIMIT_WITHDRAW, _POOL_ID));
    bytes32 internal constant _SWAP_LIMIT_KEY     = keccak256(abi.encode(_LIMIT_SWAP,     _POOL_ID));


    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_revertsWhenTickLimitsNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLimits-not-set");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTicksMisorderedBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 270_000, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 1_000_000e6);
        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_302,
            tickUpper  : 276_301,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_301,
            tickUpper  : 276_301,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_301,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickLowerTooLowBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_300, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 1_000_000e6);
        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLower-too-low");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_299,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickUpperTooHighBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 270_000, 276_600, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 1_000_000e6);
        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickUpper-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_601,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickSpacingTooWideBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_300, 276_600, 100);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 1_000_000e6);
        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickSpacing-too-wide");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_400,
            tickUpper  : 276_501,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_400,
            tickUpper  : 276_500,
            liquidity  : 1_000_000e12,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenMaxAmountsSurpassedBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 270_000, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(_POOL_ID, 276_300, 276_400, 1_000_000e12);

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted - 1, amount0Forecasted)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_400,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Forecasted - 1,
            amount1Max : amount1Forecasted
        });

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted - 1, amount1Forecasted)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_400,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted - 1
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_400,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });
    }

    function test_mintPositionUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        uint256 expectedDecrease = 29_773.913458368778256533e18;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 270_000, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_000,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 276_000,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted
        });
    }

    function test_mintPositionUniswapV4() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 270_000, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(_POOL_ID, 276_000, 276_600, 1_000_000e12, 0.99e18);

        vm.record();

        IncreasePositionResult memory result = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : 276_000,
            tickUpper  : 276_600,
            liquidity  : 1_000_000e12,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 12_871.843781e6);
        assertEq(result.amount1Spent, 16_902.069677368778256533e18);
    }

    /**********************************************************************************************/
    /*** increaseLiquidity Tests                                                                ***/
    /**********************************************************************************************/

    function test_increaseLiquidityUniswapV4_revertsWhenPositionIsNotOwnedByProxy() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(address(almProxy));
        IPositionManagerLike(_POSITION_MANAGER).transferFrom(address(almProxy), address(1), minted.tokenId);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/non-proxy-position");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/poolKey-poolId-mismatch");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickLowerTooLowBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_001, 276_600, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickLower-too-low");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 1_000);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickUpperTooHighBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_599, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickUpper-too-high");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 1_000);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTickSpacingTooWideBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 599);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/tickSpacing-too-wide");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 600);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenMaxAmountsMaxSurpassedBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted - 1, amount0Forecasted)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted - 1,
            amount1Max        : amount1Forecasted
        });

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted - 1, amount1Forecasted)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted - 1
        });

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        uint256 expectedDecrease = 29_773.913458368778256533e18;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);
        vm.stopPrank();

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12
        );

        amount0Forecasted += 1; // Quote is off by 1
        amount1Forecasted += 1; // Quote is off by 1

        deal(address(usdt), address(almProxy), amount0Forecasted);
        deal(address(usds), address(almProxy), amount1Forecasted);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e12,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted
        });
    }

    function test_increaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_000, 276_600, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint128 amount0Max, uint128 amount1Max ) = _getIncreasePositionMaxAmounts(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            1_000_000e12,
            0.99e18
        );

        vm.record();

        IncreasePositionResult memory result = _increasePosition(
            minted.tokenId,
            1_000_000e12,
            amount0Max,
            amount1Max
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 12_871.843781e6);
        assertEq(result.amount1Spent, 16_902.069677368778256533e18);
    }

    /**********************************************************************************************/
    /*** decreaseLiquidityUniswapV4 Tests                                                       ***/
    /**********************************************************************************************/

    function test_decreaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/poolKey-poolId-mismatch");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount0MinNotMetBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount0Forecasted + 1,
                amount0Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted + 1,
            amount1Min        : amount1Forecasted
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount1MinNotMetBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount1Forecasted + 1,
                amount1Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted + 1
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        uint256 expectedDecrease = 14_886.956728684389128266e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease - 1, 0);

        ( uint128 amount0Forecasted, uint128 amount1Forecasted ) = _quoteLiquidity(
            _POOL_ID,
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_partial() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Min, uint128 amount1Min ) = _getDecreasePositionMinAmounts(
            minted.tokenId,
            minted.liquidityIncrease / 2,
            0.99e18
        );

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(
            minted.tokenId,
            minted.liquidityIncrease / 2,
            amount0Min,
            amount1Min
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 6_435.921890e6);
        assertEq(result.amount1Received, 8_451.034838684389128266e18);
    }

    function test_decreaseLiquidityUniswapV4_all() external {
        IncreasePositionResult memory minted = _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000e12);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint128 amount0Min, uint128 amount1Min ) = _getDecreasePositionMinAmounts(
            minted.tokenId,
            minted.liquidityIncrease,
            0.99e18
        );

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(
            minted.tokenId,
            minted.liquidityIncrease,
            amount0Min,
            amount1Min
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 12_871.843780e6);
        assertEq(result.amount1Received, 16_902.069677368778256532e18);
    }

    /**********************************************************************************************/
    /*** swapUniswapV4 Tests                                                                    ***/
    /**********************************************************************************************/

    function test_swapUniswapV4_revertsWhenMaxSlippageNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/max-slippage-not-set");
        mainnetController.swapUniswapV4(_POOL_ID, address(0), 0, 0);
    }

    function test_swapUniswapV4_revertsWhenRateLimitExceededBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 10_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usdt), 10_000e6, 0.99e18);

        deal(address(usdt), address(almProxy), 10_000e6 + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUniswapV4({
            poolId       : _POOL_ID,
            tokenIn      : address(usdt),
            amountIn     : 10_000e6 + 1,
            amountOutMin : amountOutMin
        });

        vm.prank(relayer);
        mainnetController.swapUniswapV4({
            poolId       : _POOL_ID,
            tokenIn      : address(usdt),
            amountIn     : 10_000e6,
            amountOutMin : amountOutMin
        });
    }

    function test_swapUniswapV4_revertsWhenInputTokenNotForPool() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/invalid-tokenIn");
        mainnetController.swapUniswapV4(_POOL_ID, address(dai), 10_000e6, 10_000e6);
    }

    function test_swapUniswapV4_revertsWhenAmountOutMinTooLowBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 10_000e6);

        vm.prank(relayer);
        vm.expectRevert("UniswapV4Lib/amountOutMin-too-low");
        mainnetController.swapUniswapV4(_POOL_ID, address(usdt), 10_000e6, 9_800e18 - 1);

        vm.prank(relayer);
        mainnetController.swapUniswapV4(_POOL_ID, address(usdt), 10_000e6, 9_800e18);
    }

    function test_swapUniswapV4_revertsWhenAmountOutMinNotMetBoundary() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdt), address(almProxy), 10_000e6);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                IV4RouterLike.V4TooLittleReceived.selector,
                9_963.585379886102636344e18 + 1,
                9_963.585379886102636344e18
            )
        );

        mainnetController.swapUniswapV4(_POOL_ID, address(usdt), 10_000e6, 9_963.585379886102636344e18 + 1);

        vm.prank(relayer);
        mainnetController.swapUniswapV4(_POOL_ID, address(usdt), 10_000e6, 9_963.585379886102636344e18);
    }

    function test_swapUniswapV4_token0toToken1() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usdt), 10_000e6, 0.99e18);

        vm.record();

        uint256 amountOut = _swap(_POOL_ID, address(usdt), 10_000e6, amountOutMin);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 9_963.585379886102636344e18);
    }

    function test_swapUniswapV4_token1toToken0() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        uint128 amountOutMin = _getSwapAmountOutMin(_POOL_ID, address(usds), 3_000e18, 0.99e18);

        vm.record();

        uint256 amountOut = _swap(_POOL_ID, address(usds), 3_000e18, amountOutMin);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 2_990.034994e6);
    }

    /**********************************************************************************************/
    /*** Fuzz Tests                                                                             ***/
    /**********************************************************************************************/

    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_mintAndDecreaseFullAmounts(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    )
        external
    {
        tickLower = int24(_bound(int256(tickLower), 100_000, 300_000 - 1));

        int256 boundedUpperMax = int256(tickLower) + 1_000 > 400_000 ? int256(400_000) : int256(tickLower) + 1_000;

        tickUpper = int24(_bound(int256(tickUpper), int256(tickLower) + 1, boundedUpperMax));
        liquidity = uint128(_bound(uint256(liquidity), 1e6, 1_000_000_000e12));

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 100_000, 400_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  1_000_000_000e18, uint256(1_000_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 1_000_000_000e18, uint256(1_000_000_000e18) / 1 days);
        vm.stopPrank();

        IncreasePositionResult memory mintResult     = _mintPosition(_POOL_ID, tickLower, tickUpper, liquidity, type(uint128).max, type(uint128).max);
        DecreasePositionResult memory decreaseResult = _decreasePosition(mintResult.tokenId, mintResult.liquidityIncrease, 0, 0);

        uint256 valueDeposited = mintResult.amount0Spent        + mintResult.amount1Spent;
        uint256 valueReceived  = decreaseResult.amount0Received + decreaseResult.amount1Received;

        assertApproxEqAbs(valueReceived, valueDeposited, 2);
    }

    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_increaseAndDecreaseFullAmounts(
        int24   tickLower,
        int24   tickUpper,
        uint128 initialLiquidity
    )
        external
    {
        tickLower = int24(_bound(int256(tickLower), 100_000, 300_000 - 1));

        int256 boundedUpperMax = int256(tickLower) + 1_000 > 400_000 ? int256(400_000) : int256(tickLower) + 1_000;

        tickUpper        = int24(_bound(int256(tickUpper), int256(tickLower) + 1, boundedUpperMax));
        initialLiquidity = uint128(_bound(uint256(initialLiquidity), 1e6, 2_000_000e12));

        uint128 additionalLiquidity = initialLiquidity / 2;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 100_000, 400_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        IncreasePositionResult memory mintResult     = _mintPosition(_POOL_ID, tickLower, tickUpper, initialLiquidity, type(uint128).max, type(uint128).max);
        IncreasePositionResult memory increaseResult = _increasePosition(mintResult.tokenId, additionalLiquidity, type(uint128).max, type(uint128).max);

        uint256 valueBeforeIncrease = mintResult.amount0Spent     + mintResult.amount1Spent;
        uint256 valueAdded          = increaseResult.amount0Spent + increaseResult.amount1Spent;
        uint256 totalValueDeposited = valueBeforeIncrease + valueAdded;

        uint128 totalLiquidity = mintResult.liquidityIncrease + increaseResult.liquidityIncrease;

        DecreasePositionResult memory decreaseResult = _decreasePosition(mintResult.tokenId, totalLiquidity, 0, 0);

        uint256 valueReceived = decreaseResult.amount0Received + decreaseResult.amount1Received;

        assertApproxEqAbs(totalValueDeposited, valueReceived, 10);
    }

    /// @param swapDirection true = USDT->USDS, false = USDS->USDT
    /// forge-config: default.fuzz.runs = 100
    function testFuzz_uniswapV4_swapUniswapV4_amounts(uint128 amountIn, bool swapDirection)
        external
    {
        // Needed due to low liquidity currently in the pool.
        _setupLiquidity(_POOL_ID, 276_000, 276_600, 1_000_000_000e12);

        if (swapDirection) {
            amountIn = uint128(_bound(uint256(amountIn), 1e6, 1_000_000e6));
        } else {
            amountIn = uint128(_bound(uint256(amountIn), 1e18, 1_000_000e18));
        }

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        rateLimits.setRateLimitData(_SWAP_LIMIT_KEY, 1_000_000e18, 0);
        vm.stopPrank();

        address tokenIn = swapDirection ? address(usdt) : address(usds);

        uint128 amountOutMin    = _getSwapAmountOutMin(_POOL_ID, tokenIn, amountIn, 0.99e18);
        uint256 rateLimitBefore = rateLimits.getCurrentRateLimit(_SWAP_LIMIT_KEY);
        uint256 amountOut       = _swap(_POOL_ID, tokenIn, amountIn, amountOutMin);

        assertEq(
            rateLimits.getCurrentRateLimit(_SWAP_LIMIT_KEY),
            rateLimitBefore - (swapDirection ? _to18From6Decimals(amountIn) : amountIn)
        );

        assertGe(amountOut, amountOutMin);

        if (swapDirection) {
            assertApproxEqRel(_to18From6Decimals(amountIn), amountOut, 0.005e18);
        } else {
            assertApproxEqRel(amountIn, _to18From6Decimals(amountOut), 0.005e18);
        }
    }

    /**********************************************************************************************/
    /*** Story Tests                                                                            ***/
    /**********************************************************************************************/

    /**
     * @dev Story 1 is a round trip of liquidity minting, increase, decreasing, and closing/burning,
     *      each 90 days apart, while an external account swaps tokens in and out of the pool.
     *      - The relayer mints a position with 400_000_000e12 liquidity.
     *      - The relayer increases the liquidity position by 50% (to 200_000_000e12 liquidity).
     *      - The relayer decreases the liquidity position by 50% (to 300_000_000e12 liquidity).
     *      - The relayer decreases the remaining liquidity position (to 0 liquidity).
     */
    function test_uniswapV4_story1() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 276_300, 280_000, 1_000);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        // 1. The relayer mints a position with 1,000,000 liquidity.
        IncreasePositionResult memory increaseResult = _mintPosition({
            poolId     : _POOL_ID,
            tickLower  : 276_300,
            tickUpper  : 276_400,
            liquidity  : 4_000e17,
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max
        });

        assertEq(increaseResult.amount0Spent, 1_183_957.816516e6);
        assertEq(increaseResult.amount1Spent, 813_048.360317266265664850e18);

        uint256 expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + increaseResult.amount1Spent;
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 2. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 3. Some account swaps 500,000 USDT for USDS.
        assertEq(_externalSwap(_POOL_ID, _user, address(usdt), 500_000e6), 500_159.667307969852203416e18);

        // 4. The relayer increases the liquidity position by 50%.
        increaseResult = _increasePosition(increaseResult.tokenId, 2_000e17, type(uint128).max, type(uint128).max);

        assertEq(increaseResult.amount0Spent, 840_712.962029e6);
        assertEq(increaseResult.amount1Spent, 157_636.030550204975395201e18);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + increaseResult.amount1Spent;
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 5. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 6. Some account swaps 750,000 USDS for USDT.
        assertEq(_externalSwap(_POOL_ID, _user, address(usds), 750_000e18), 749_609.539364e6);

        // 7. The relayer decreases the liquidity position by 50%.
        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 3_000e17, 0, 0);

        assertEq(decreaseResult.amount0Received, 887_531.893676e6);
        assertEq(decreaseResult.amount1Received, 610_298.227601444650560686e18);

        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + decreaseResult.amount1Received;
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 8. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 9. Some account swaps 200,000 USDT for USDS.
        assertEq(_externalSwap(_POOL_ID, _user, address(usdt), 200_000e6), 200_180.816044995828458470e18);

        // 10. The relayer decreases the remaining liquidity position.
        decreaseResult = _decreasePosition(increaseResult.tokenId, 3_000e17, 0, 0);

        assertEq(decreaseResult.amount0Received, 1_086_263.185036e6);
        assertEq(decreaseResult.amount1Received, 411_312.505850170682613151e18);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + decreaseResult.amount1Received;
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(decreaseResult.tokenId),
            0
        );
    }

}
