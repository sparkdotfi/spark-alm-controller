// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { FullMath }         from "../../lib/dss-allocator/src/funnels/uniV3/FullMath.sol";
import { LiquidityAmounts } from "../../lib/dss-allocator/src/funnels/uniV3/LiquidityAmounts.sol";
import { TickMath }         from "../../lib/dss-allocator/src/funnels/uniV3/TickMath.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { IERC20 as IERC20OZ } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }          from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";
import { UniswapV3Utils }  from "../../src/facets/uniswap-v3/UniswapV3Utils.sol";

import {
    INonfungiblePositionManager,
    ISwapRouter,
    IUniswapV3PoolLike
} from "../interfaces/UniswapV3.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC721Like {

    function transferFrom(address from, address to, uint256 tokenId) external;

}

abstract contract UniswapV3_TestBase is ForkTestBase {

    address constant UNISWAP_V3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address constant UNISWAP_V3_DAI_USDC_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;

    int24 internal constant DEFAULT_TICK_LOWER = -600;
    int24 internal constant DEFAULT_TICK_UPPER =  600;

    bytes32 uniswapV3_UsdcUsdtPool_UsdcSwapKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdtSwapKey;
    bytes32 uniswapV3_UsdcUsdtPool_AggregateAddLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_RemoveLiquidityKey;

    bytes32 uniswapV3_DaiUsdcPool_DaiSwapKey;
    bytes32 uniswapV3_DaiUsdcPool_UsdcSwapKey;
    bytes32 uniswapV3_DaiUsdcPool_AggregateAddLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_DaiAddLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_RemoveLiquidityKey;

    IUniswapV3PoolLike internal pool;
    IERC20             internal token0;
    IERC20             internal token1;
    uint24             internal poolFee;
    uint8              internal token0Decimals;
    int24              internal initTick;
    int24              internal tickSpacing;

    address internal stranger;

    function setUp() public virtual override  {
        super.setUp();

        stranger = makeAddr("stranger");

        uniswapV3_UsdcUsdtPool_UsdcSwapKey = mainnetController.getUniswapV3SwapRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL,
            address(usdc)
        );

        uniswapV3_UsdcUsdtPool_UsdtSwapKey = mainnetController.getUniswapV3SwapRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL,
            address(usdt)
        );

        uniswapV3_UsdcUsdtPool_AggregateAddLiquidityKey = mainnetController.getUniswapV3AggregateDepositRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL
        );

        uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey = mainnetController.getUniswapV3AssetDepositRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL,
            address(usdc)
        );

        uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey = mainnetController.getUniswapV3AssetDepositRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL,
            address(usdt)
        );

        uniswapV3_UsdcUsdtPool_RemoveLiquidityKey = mainnetController.getUniswapV3WithdrawRateLimitKey(
            UNISWAP_V3_USDC_USDT_POOL
        );

        uniswapV3_DaiUsdcPool_DaiSwapKey = mainnetController.getUniswapV3SwapRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL,
            address(dai)
        );

        uniswapV3_DaiUsdcPool_UsdcSwapKey = mainnetController.getUniswapV3SwapRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL,
            address(usdc)
        );

        uniswapV3_DaiUsdcPool_AggregateAddLiquidityKey = mainnetController.getUniswapV3AggregateDepositRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL
        );

        uniswapV3_DaiUsdcPool_DaiAddLiquidityKey = mainnetController.getUniswapV3AssetDepositRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL,
            address(dai)
        );

        uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey = mainnetController.getUniswapV3AssetDepositRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL,
            address(usdc)
        );

        uniswapV3_DaiUsdcPool_RemoveLiquidityKey = mainnetController.getUniswapV3WithdrawRateLimitKey(
            UNISWAP_V3_DAI_USDC_POOL
        );

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcSwapKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtSwapKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_DaiSwapKey,   1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_UsdcSwapKey,  1_000_000e6,  uint256(1_000_000e6)  / 1 days);

        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_AggregateAddLiquidityKey, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey,      1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey,      1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_AggregateAddLiquidityKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_DaiAddLiquidityKey,        1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey,       1_000_000e6,  uint256(1_000_000e6)  / 1 days);

        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_RemoveLiquidityKey, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_RemoveLiquidityKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);

        // Set a higher slippage to allow for successes
        mainnetController.setUniswapV3MaxSlippage(_getPool(), 0.98e18);

        // All trades must have no more than 200 ticks impact on the pool. For most stablecoin pools, a tick is 1bps
        mainnetController.setUniswapV3PoolMaxTickDelta(_getPool(), 200);
        mainnetController.setUniswapV3TWAPSecondsAgo(_getPool(),   1 days);

        vm.stopPrank();

        pool           = IUniswapV3PoolLike(_getPool());
        token0         = IERC20(pool.token0());
        token1         = IERC20(pool.token1());
        poolFee        = pool.fee();
        token0Decimals = IERC20(address(token0)).decimals();
        tickSpacing    = IUniswapV3PoolLike(address(pool)).tickSpacing();

        ( , initTick, , , , , ) = pool.slot0();

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick - 1000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick + 1000);
        vm.stopPrank();
    }

    function _getSwapKey(address tokenIn) internal view returns (bytes32) {
        return mainnetController.getUniswapV3SwapRateLimitKey(_getPool(), tokenIn);
    }

    function _label() internal {
        vm.label(UNISWAP_V3_ROUTER,           'UniswapV3Router');
        vm.label(UNISWAP_V3_POSITION_MANAGER, 'UniswapV3PositionManager');
        vm.label(UNISWAP_V3_USDC_USDT_POOL,   'USDC-USDT Pool');
        vm.label(UNISWAP_V3_DAI_USDC_POOL,    'DAI-USDC Pool');
    }

    function _getPool() internal pure virtual returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function _getBlock() internal pure virtual override returns (uint256) {
        return 23677743;  // Oct 28, 2025
    }

    function _fundProxy(uint256 amount0Desired, uint256 amount1Desired) internal {
        deal(address(token0), address(almProxy), amount0Desired);
        deal(address(token1), address(almProxy), amount1Desired);
    }

    function _toSpacedTick(int24 tick) internal view returns (int24) {
        return tick / tickSpacing * tickSpacing;
    }

    function _swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    )
        internal
        returns (uint256 amountOut)
    {
        vm.startPrank(allocator);
        amountOut = mainnetController.swapUniswapV3(
            _getPool(),
            tokenIn,
            amountIn,
            minAmountOut,
            200
        );
        vm.stopPrank();
    }

    function _getCurrentPriceX192() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3PoolLike(_getPool()).slot0();
        return _priceX192(sqrtPriceX96);
    }

    function _priceX192(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1);
    }

    function _addLiquidity(
        uint256                             tokenId_,
        IUniswapV3Facet.Ticks        memory tick_,
        IUniswapV3Facet.TokenAmounts memory desired_,
        IUniswapV3Facet.TokenAmounts memory min_
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        IUniswapV3Facet.TokenAmounts memory amountsUsed;

        vm.startPrank(allocator);
        ( tokenId, liquidity, amountsUsed ) = mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId_,
            tick_,
            desired_,
            min_,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        amount0Used = amountsUsed.amount0;
        amount1Used = amountsUsed.amount1;
    }

    function _minLiquidityPosition(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (IUniswapV3Facet.TokenAmounts memory)
    {
        return IUniswapV3Facet.TokenAmounts(
            amount0 * 98 / 100,
            amount1 * 98 / 100
        );
    }

}

contract MainnetController_UniswapV3_Swap_Tests is UniswapV3_TestBase {

    function test_swapUniswapV3_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            1,
            1,
            100
        );
    }

    function test_swapUniswapV3_notAllocator() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            1,
            1,
            100
        );
    }

    function test_swapUniswapV3_invalidMaxTickDelta() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-max-tick-delta");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            type(uint24).max
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_zeroTWAPSeconds() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3TWAPSecondsAgo(_getPool(), 0);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/zero-twap-seconds");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            0
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_minAmountNotMet() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-not-set");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            200
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_invalidTokenPair() public {
        uint256 amountIn = 100_000e6;
        deal(address(dai), address(almProxy), amountIn);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-token-pair");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(dai),
            amountIn,
            1,
            200
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_slippageTooHigh() public {
        uint256 amountIn = 150_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(allocator);
        vm.expectRevert("Too little received");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            amountIn * 9999/10000,
            0
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_limitsAmountOutWhenCrossingMaxTick() public {
        uint256 amountIn = 2_000_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(token0)), 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("Too little received");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            amountIn * 999/1000,
            0 // amountOut will be capped to only liquidity that's within the current tick
        );

        vm.stopPrank();
    }

    function test_swapUniswapV3_token0ToToken1() public {
        uint256 amountIn = 250_000e6;
        _fundProxy(amountIn, 0);

        uint256 swapLimitBefore     = rateLimits.getCurrentRateLimit(_getSwapKey(address(token0)));
        uint256 token0BalanceBefore = token0.balanceOf(address(almProxy));
        uint256 token1BalanceBefore = token1.balanceOf(address(almProxy));

        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3Swap(
            _getPool(),
            address(token0),
            amountIn,
            249_932.354229e6
        );

        uint256 amountOut = _swap(address(token0), amountIn, amountIn * 999/1000);

        uint256 swapLimitAfter  = rateLimits.getCurrentRateLimit(_getSwapKey(address(token0)));

        assertApproxEqAbs(amountIn, amountOut, .0001e18, "swap output should be within 0.01% of amountIn");
        assertEq(
            token0.balanceOf(address(almProxy)),
            token0BalanceBefore - amountIn,
            "proxy should spend token0"
        );
        assertEq(
            token1.balanceOf(address(almProxy)),
            token1BalanceBefore + amountOut,
            "proxy should receive token1"
        );
        assertEq(
            swapLimitBefore - swapLimitAfter,
            amountIn,
            "swap rate limit should decrease by normalized token0 value"
        );
    }

    function test_swapUniswapV3_token1ToToken0() public {
        uint256 amountIn = 300_000e6;
        _fundProxy(0, amountIn);

        uint256 swapLimitBefore     = rateLimits.getCurrentRateLimit(_getSwapKey(address(token1)));
        uint256 token0BalanceBefore = token0.balanceOf(address(almProxy));
        uint256 token1BalanceBefore = token1.balanceOf(address(almProxy));

        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3Swap(
            _getPool(),
            address(token1),
            amountIn,
            300_018.569643e6
        );

        uint256 amountOut = _swap(address(token1), amountIn, amountIn * 999/1000);

        uint256 swapLimitAfter = rateLimits.getCurrentRateLimit(_getSwapKey(address(token1)));

        assertApproxEqAbs(amountIn, amountOut, .0001e18, "swap output should be within 0.01% of amountIn");
        assertEq(
            token1.balanceOf(address(almProxy)),
            token1BalanceBefore - amountIn,
            "proxy should spend token1"
        );
        assertEq(
            token0.balanceOf(address(almProxy)),
            token0BalanceBefore + amountOut,
            "proxy should receive token0"
        );
        assertEq(
            swapLimitBefore - swapLimitAfter,
            amountIn,
            "swap rate limit should decrease by normalized value"
        );
    }

    function test_swapUniswapV3_whenNotAllTokensInAreUsed() public {
        bytes32 swapKey = _getSwapKey(address(token0));

        // Set maxSlippage to near 0, and set infinite rate limit
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(_getPool(), 1);

        rateLimits.setRateLimitData(
            swapKey,
            type(uint256).max - 1,
            type(uint256).max / 1 days
        );
        vm.stopPrank();

        uint256 amountIn = 1_000_000_000_000e6;
        _fundProxy(amountIn, 0);

        uint256 swapLimitBefore     = rateLimits.getCurrentRateLimit(swapKey);
        uint256 token0BalanceBefore = token0.balanceOf(address(almProxy));
        uint256 token1BalanceBefore = token1.balanceOf(address(almProxy));

        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3Swap(
            _getPool(),
            address(token0),
            2_140_038.431336e6,
            2_139_359.691608e6
        );

        vm.startPrank(allocator);
        uint256 amountOut = mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            1e6,      // minAmountOut: very small amount
            1         // tickDelta: 1 tick
        );
        vm.stopPrank();

        uint256 token0BalanceAfter  = token0.balanceOf(address(almProxy));
        uint256 token1BalanceAfter  = token1.balanceOf(address(almProxy));
        uint256 swapLimitAfter      = rateLimits.getCurrentRateLimit(swapKey);

        // Net amount of token0 actually spent (after any refunds)
        uint256 spent = token0BalanceBefore - token0BalanceAfter;

        // Sanity checks: we spent some, but not all, of amountIn
        assertGt(spent, 0, "proxy should spend some token0");
        assertGt(amountOut, 0, "swap should return some token1");
        assertLt(
            spent,
            amountIn,
            "not all input tokens should be used (partial fill due to price limit)"
        );

        // Proxy should receive amountOut of token1
        assertEq(
            token1BalanceAfter,
            token1BalanceBefore + amountOut,
            "proxy should receive token1"
        );

        // (a) Rate limit decreased by the actual amount spent, not by amountIn
        assertEq(
            swapLimitBefore - swapLimitAfter,
            spent,
            "swap rate limit should decrease by the actual token0 spent"
        );

        // (b) Approvals to the router should be cleared back to zero
        assertEq(
            token0.allowance(address(almProxy), UNISWAP_V3_ROUTER),
            0,
            "router allowance for token0 should be cleared after swap"
        );
    }

}

abstract contract UniswapV3_E2ETestBase is UniswapV3_TestBase {

    function _e2eSwapUniswapV3(uint256 swapAmount, IERC20 tokenIn, IERC20 tokenOut, bytes32 swapKey) internal {
        deal(address(tokenIn), address(almProxy), swapAmount);

        uint8 tokenInDecimals  = IERC20(address(tokenIn)).decimals();
        uint8 tokenOutDecimals = IERC20(address(tokenOut)).decimals();

        uint256 swapAmountOut = FullMath.mulDiv(swapAmount, 10**tokenOutDecimals, 10**tokenInDecimals);

        uint256 tokenOutBalanceBeforeSwap = tokenOut.balanceOf(address(almProxy));

        uint256 swapRateLimitBefore = rateLimits.getCurrentRateLimit(swapKey);

        vm.startPrank(allocator);
        uint256 amountOut = mainnetController.swapUniswapV3(
            _getPool(),
            address(tokenIn),
            swapAmount,
            swapAmountOut * 999 / 1000,
            200 // allow for price impact of up to 2 points
        );
        vm.stopPrank();

        uint256 normalizedAmountOut = FullMath.mulDiv(amountOut, 10**tokenInDecimals, 10**tokenOutDecimals);

        assertApproxEqRel(
            normalizedAmountOut,
            swapAmount,
            0.005e18,
            "normalizedAmountOut should be within 0.05% of swapAmount"
        );

        assertEq(
            tokenIn.balanceOf(address(almProxy)),
            0,
            "tokenIn balance of almProxy should be 0"
        );

        assertEq(
            tokenOut.balanceOf(address(almProxy)),
            tokenOutBalanceBeforeSwap + amountOut,
            "tokenOut balance of almProxy should be equal to tokenOutBalanceBeforeSwap + amountOut"
        );

        assertEq(
            rateLimits.getCurrentRateLimit(swapKey),
            swapRateLimitBefore - swapAmount,
            "swap rate limit should be equal to swapRateLimitBefore - swapAmount"
        );
    }

}

contract MainnetController_UniswapV3_DAIUSDC_E2ETests is UniswapV3_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function test_e2e_swapUniswapV3_DAIToUSDC(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1_000_000e18);

        _e2eSwapUniswapV3(swapAmount, dai, usdc, _getSwapKey(address(dai)));
    }

    function test_e2e_swapUniswapV3_DAIToUSDC_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e18, 2_000_000e18);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(dai)), 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        _e2eSwapUniswapV3(swapAmount, dai, usdc, _getSwapKey(address(dai)));
    }

    function test_e2e_swapUniswapV3_USDCToDAI(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2eSwapUniswapV3(swapAmount, usdc, dai, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_USDCToDAI_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 2_000_000e6);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdc)), 2_000_000e6, uint256(2_000_000e6) / 1 days);
        vm.stopPrank();

        _e2eSwapUniswapV3(swapAmount, usdc, dai, _getSwapKey(address(usdc)));
    }

}

contract MainnetController_UniswapV3_USDCUSDT_E2ETests is UniswapV3_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function test_e2e_swapUniswapV3_USDCToUSDT(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2eSwapUniswapV3(swapAmount, usdc, usdt, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_USDCToUSDT_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 5_000_000e6);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdc)), 5_000_000e6, uint256(5_000_000e6) / 1 days);
        vm.stopPrank();

        _e2eSwapUniswapV3(swapAmount, usdc, usdt, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_USDTToUSDC(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2eSwapUniswapV3(swapAmount, usdt, usdc, _getSwapKey(address(usdt)));
    }

    function test_e2e_swapUniswapV3_USDTToUSDC_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 5_000_000e6);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdt)), 5_000_000e6, uint256(5_000_000e6) / 1 days);
        vm.stopPrank();

        _e2eSwapUniswapV3(swapAmount, usdt, usdc, _getSwapKey(address(usdt)));
    }

}

contract MainnetController_UniswapV3_AddLiquidity_FailureTests is UniswapV3_TestBase {

    function _defaultTickRange() internal view returns (IUniswapV3Facet.Ticks memory) {
        return IUniswapV3Facet.Ticks({ lower: _toSpacedTick(initTick - 100), upper: _toSpacedTick(initTick + 100) });
    }

    function _defaultDesiredPosition() internal view returns (IUniswapV3Facet.TokenAmounts memory) {
        uint256 amount0 = 1000 * 10 ** uint256(token0Decimals);
        uint256 amount1 = 1000 * 10 ** uint256(IERC20(address(token1)).decimals());

        return IUniswapV3Facet.TokenAmounts({ amount0: amount0, amount1: amount1 });
    }

    function _defaultMinPosition(IUniswapV3Facet.TokenAmounts memory desired)
        internal
        pure
        returns (IUniswapV3Facet.TokenAmounts memory)
    {
        return IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 99 / 100,
            amount1: desired.amount1 * 99 / 100
        });
    }

    function _prepareDefaultAddLiquidity()
        internal
        returns (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        )
    {
        tick = _defaultTickRange();
        desired = _defaultDesiredPosition();
        min = _defaultMinPosition(desired);
        _fundProxy(desired.amount0, desired.amount1);
    }

    function _buildMintParams(
        IUniswapV3Facet.Ticks        memory tick,
        IUniswapV3Facet.TokenAmounts memory desired,
        IUniswapV3Facet.TokenAmounts memory min,
        uint256                             deadline
    ) internal view returns (INonfungiblePositionManager.MintParams memory) {
        return INonfungiblePositionManager.MintParams({
            token0         : address(token0),
            token1         : address(token1),
            fee            : poolFee,
            tickLower      : tick.lower,
            tickUpper      : tick.upper,
            amount0Desired : desired.amount0,
            amount1Desired : desired.amount1,
            amount0Min     : min.amount0,
            amount1Min     : min.amount1,
            recipient      : address(almProxy),
            deadline       : deadline
        });
    }

    function _mockOwnerOf(uint256 tokenId) internal {
        vm.mockCall(
            UNISWAP_V3_POSITION_MANAGER,
            abi.encodeCall(INonfungiblePositionManager.ownerOf, (tokenId)),
            abi.encode(address(almProxy))
        );
    }

    function _mintExternalPosition() internal returns (uint256 tokenId) {
        uint256 amount0 = 5 * 10 ** uint256(token0Decimals);
        uint8 token1Decimals = IERC20(address(token1)).decimals();
        uint256 amount1 = 5 * 10 ** uint256(token1Decimals);

        deal(address(token0), stranger, amount0);
        deal(address(token1), stranger, amount1);

        vm.startPrank(stranger);
        SafeERC20.forceApprove(IERC20OZ(address(token0)), UNISWAP_V3_POSITION_MANAGER, amount0);
        SafeERC20.forceApprove(IERC20OZ(address(token1)), UNISWAP_V3_POSITION_MANAGER, amount1);
        (tokenId,,,) = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: poolFee,
                tickLower: _toSpacedTick(initTick - 50),
                tickUpper: _toSpacedTick(initTick + 50),
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: stranger,
                deadline: block.timestamp + 1 hours
            })
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_reentrancy() external {
        _setControllerEntered();

        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
    }

    function test_addLiquidityUniswapV3_notAllocator() public {
        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                ALLOCATOR_ROLE
            )
        );
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
    }

    function test_addLiquidityUniswapV3_noLiquidityIncrease() public {
        (IUniswapV3Facet.Ticks memory tick, IUniswapV3Facet.TokenAmounts memory desired, IUniswapV3Facet.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        uint256 deadline = block.timestamp + 1 hours;

        INonfungiblePositionManager.MintParams memory mintParams = _buildMintParams(tick, desired, min, deadline);

        vm.mockCall(
            UNISWAP_V3_POSITION_MANAGER,
            abi.encodeCall(INonfungiblePositionManager.mint, (mintParams)),
            abi.encode(uint256(1), uint128(0), uint256(0), uint256(0))
        );

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/no-liquidity-increased");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            deadline
        );
        vm.stopPrank();
        vm.clearMockedCalls();
    }

    function test_addLiquidityUniswapV3_zeroAmount() public {
        IUniswapV3Facet.Ticks memory tick = _defaultTickRange();
        IUniswapV3Facet.TokenAmounts memory zeroPosition = IUniswapV3Facet.TokenAmounts({
            amount0: 0,
            amount1: 0
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/zero-amount");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            zeroPosition,
            zeroPosition,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_maxSlippageNotSet() public {
        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(_getPool(), 0);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/max-slippage-not-set");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_invalidTickLower() public {
        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        tick.lower = initTick - 2000;

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/lower-tick-outside-bounds");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_invalidTickUpper() public {
        (
            IUniswapV3Facet.Ticks memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        tick.upper = initTick + 2000;

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/upper-tick-outside-bounds");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_minAmount0BelowBound() public {
        ( IUniswapV3Facet.Ticks memory tick, IUniswapV3Facet.TokenAmounts memory desired, ) = _prepareDefaultAddLiquidity();

        IUniswapV3Facet.TokenAmounts memory min = IUniswapV3Facet.TokenAmounts({
            amount0: 0,
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_minAmount1BelowBound() public {
        ( IUniswapV3Facet.Ticks memory tick, IUniswapV3Facet.TokenAmounts memory desired, ) = _prepareDefaultAddLiquidity();

        IUniswapV3Facet.TokenAmounts memory min = IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: 0
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_proxyDoesNotOwnTokenId() public {
        uint256 tokenId = _mintExternalPosition();

        vm.warp(block.timestamp + 1 hours);

        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/proxy-does-not-own-token-id");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_zeroMaxAmount_token0() public {
        uint256 amount0 = 1_000_000e6;
        uint256 amount1 = 0;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey, 0, 0);

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: initTick + 50,
                upper: initTick + 100
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_zeroMaxAmount_token1() public {
        uint256 amount0 = 0;
        uint256 amount1 = 1_000_000e6;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey, 0, 0);

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: initTick - 100,
                upper: initTick - 50
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_zeroMaxAmount_aggregate() public {
        uint256 amount0 = 1_000_000e18;
        uint256 amount1 = 0;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_AggregateAddLiquidityKey, 0, 0);

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: initTick + 50,
                upper: initTick + 100
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_rateLimitExceeded_aggregate() public {
        uint256 amount0 = 3_000_000e18;
        uint256 amount1 = 0;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey);
        rateLimits.setUnlimitedRateLimitData(uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey);
        vm.stopPrank();

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: initTick + 50,
                upper: initTick + 100
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_rateLimitExceeded_token0() public {
        uint256 amount0 = 2_000_000e18;
        uint256 amount1 = 0;

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(initTick+50),
                upper: _toSpacedTick(initTick+100)
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_rateLimitExceeded_token1() public {
        uint256 amount0 = 0;
        uint256 amount1 = 2_000_000e6;

        _fundProxy(amount0, amount1);

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(initTick-100),
                upper: _toSpacedTick(initTick-50)
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_invalidPoolForPosition() public {
        // Set arbitrary values
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(UNISWAP_V3_DAI_USDC_POOL, 0.000001 * 1e18);
        mainnetController.setUniswapV3TWAPSecondsAgo(UNISWAP_V3_DAI_USDC_POOL, 1 seconds);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(UNISWAP_V3_DAI_USDC_POOL, -100000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(UNISWAP_V3_DAI_USDC_POOL, 100000);
        vm.stopPrank();

        // Mint a USDC-USDT position and transfer it to the allocator
        uint256 usdcUsdtTokenId = _mintExternalPosition();

        vm.prank(stranger);
        IERC721Like(UNISWAP_V3_POSITION_MANAGER).transferFrom(stranger, address(almProxy), usdcUsdtTokenId);

        vm.warp(block.timestamp + 1 hours);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-pool");
        mainnetController.addLiquidityUniswapV3(
            UNISWAP_V3_DAI_USDC_POOL,
            usdcUsdtTokenId, // USDC-USDT pool token ID
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(-10000),
                upper: _toSpacedTick(10000)
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 1,
                amount1: 1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 0,
                amount1: 0
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_failsAfterLowerTickBoundChanges() public {
        // Create new default position
        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.prank(allocator);
        ( uint256 tokenId, , ) = mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );

        // Change tick bounds
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), _toSpacedTick(tick.lower + 10));

        // Adding liquidity with the same tick bounds before the change should fail
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/lower-tick-outside-bounds");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_failsAfterUpperTickBoundChanges() public {
        // Create new default position
        (
            IUniswapV3Facet.Ticks        memory tick,
            IUniswapV3Facet.TokenAmounts memory desired,
            IUniswapV3Facet.TokenAmounts memory min
        ) = _prepareDefaultAddLiquidity();

        vm.prank(allocator);
        ( uint256 tokenId, , ) = mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );

        // Change tick bounds
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), _toSpacedTick(tick.upper - 10));

        // Adding liquidity with the same tick bounds before the change should fail
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/upper-tick-outside-bounds");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_failsIfLowerTickNotMultipleOfSpacing() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(UNISWAP_V3_DAI_USDC_POOL, 0.000001 * 1e18);
        mainnetController.setUniswapV3TWAPSecondsAgo(UNISWAP_V3_DAI_USDC_POOL, 1 seconds);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(UNISWAP_V3_DAI_USDC_POOL, -100000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(UNISWAP_V3_DAI_USDC_POOL, 100000);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-lower-tick");
        mainnetController.addLiquidityUniswapV3(
            UNISWAP_V3_DAI_USDC_POOL,
            0,
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(-123), // invalid tick spacing
                upper: _toSpacedTick(10000)
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 1,
                amount1: 1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 0,
                amount1: 0
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_failsIfUpperTickNotMultipleOfSpacing() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(UNISWAP_V3_DAI_USDC_POOL, 0.000001 * 1e18);
        mainnetController.setUniswapV3TWAPSecondsAgo(UNISWAP_V3_DAI_USDC_POOL, 1 seconds);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(UNISWAP_V3_DAI_USDC_POOL, -100000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(UNISWAP_V3_DAI_USDC_POOL, 100000);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-upper-tick");
        mainnetController.addLiquidityUniswapV3(
            UNISWAP_V3_DAI_USDC_POOL,
            0,
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(-10000),
                upper: _toSpacedTick(123) // invalid tick spacing
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 1,
                amount1: 1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: 0,
                amount1: 0
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_addLiquidityUniswapV3_zeroTWAPSecondsAgo() public {
        uint256 amount0 = 0;
        uint256 amount1 = 2_000_000e6;

        _fundProxy(amount0, amount1);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3TWAPSecondsAgo(_getPool(), 0);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/zero-twap-seconds");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            IUniswapV3Facet.Ticks({
                lower: _toSpacedTick(initTick-100),
                upper: _toSpacedTick(initTick-50)
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            IUniswapV3Facet.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

}

contract MainnetController_UniswapV3_AddLiquidity_TWAPProtectionTests is UniswapV3_TestBase {

    function _defaultDesiredPosition() internal view returns (IUniswapV3Facet.TokenAmounts memory) {
        uint256 amount0 = 10_000 * 10 ** uint256(token0Decimals);
        uint256 amount1 = 10_000 * 10 ** uint256(IERC20(address(token1)).decimals());

        return IUniswapV3Facet.TokenAmounts(amount0, amount1);
    }

    function _mockSpotTick(int24 spotTick) internal {
        // Mock slot0 to return a manipulated spot tick
        // slot0 returns: (sqrtPriceX96, tick, observationIndex, observationCardinality, observationCardinalityNext, feeProtocol, unlocked)
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(spotTick);
        vm.mockCall(
            _getPool(),
            abi.encodeWithSignature("slot0()"),
            abi.encode(sqrtPriceX96, spotTick, uint16(0), uint16(1), uint16(1), uint8(0), true)
        );
    }

    function _mockTwapTick(int24 twapTick) internal {
        // Mock pool.observe so that UniswapV3Utils.consult returns arithmeticMeanTick == twapTick.
        // consult divides (tickCumulatives[1] - tickCumulatives[0]) by int32(secondsAgo), so we
        // pick cumulatives whose delta is exactly twapTick * secondsAgo.
        uint32 twapSecondsAgo = mainnetController.getUniswapV3TWAPSecondsAgo(_getPool());

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(twapTick) * int56(int32(twapSecondsAgo));

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[0] = 0;
        secondsPerLiquidityCumulativeX128s[1] = 1; // Non-zero to avoid div-by-zero in consult

        vm.mockCall(
            _getPool(),
            abi.encodeWithSelector(IUniswapV3PoolLike.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // Transaction fails when spot price has been manipulated out of expected range
    // Even with valid TWAP-based min amounts, Uniswap's own slippage check fails
    // because spot price requires different token ratios than our mins allow
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenSpotPriceManipulated() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP (which is close to spot in normal conditions)
        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // Mock spot price to be way above our tick range (manipulated)
        // At this spot price, Uniswap will want mostly token1, not the balanced amounts we're providing
        _mockSpotTick(tick.upper + 1000);

        // Min amounts are valid per TWAP, but spot price is manipulated
        // Uniswap's mint will fail because actual amounts needed don't match our mins
        IUniswapV3Facet.TokenAmounts memory minAmounts = IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(allocator);
        vm.expectRevert("Price slippage check");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            minAmounts,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    // When TWAP tick is above tick.upper, expectedAmount0 = 0
    // So minAmount0 must be 0, otherwise revert
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenTWAPAboveRangeAndMinAmount0NonZero() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Set governance bounds entirely below the current TWAP
        // Pool's TWAP is near initTick, so setting bounds below that puts TWAP above our allowed range
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick - 300);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick - 100);
        vm.stopPrank();

        // Allocator uses ticks within governance bounds
        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks({
            lower: _toSpacedTick(initTick - 200),
            upper: _toSpacedTick(initTick - 100)
        });

        // Incorrectly provide non-zero minAmount0 when TWAP expects only token1
        IUniswapV3Facet.TokenAmounts memory minAmounts = IUniswapV3Facet.TokenAmounts({
            amount0: 1, // Should be 0 when twapTick > tick.upper
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            minAmounts,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    // When TWAP tick is below tick.lower, expectedAmount1 = 0
    // So minAmount1 must be 0, otherwise revert
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenTWAPBelowRangeAndMinAmount1NonZero() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Set governance bounds entirely above the current TWAP
        // Pool's TWAP is near initTick, so setting bounds above that puts TWAP below our allowed range
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick + 100);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick + 300);
        vm.stopPrank();

        // Allocator uses ticks within governance bounds
        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks({
            lower: _toSpacedTick(initTick + 100),
            upper: _toSpacedTick(initTick + 200)
        });

        // Incorrectly provide non-zero minAmount1 when TWAP expects only token0
        IUniswapV3Facet.TokenAmounts memory minAmounts = IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: 1 // Should be 0 when twapTick < tick.lower
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            minAmounts,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    // When TWAP is within tick range, minAmount0 must meet threshold
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenMinAmount0TooLow() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP, so both tokens are expected
        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // minAmount0 is too low (50%) while maxSlippage requires 98%
        IUniswapV3Facet.TokenAmounts memory minAmounts = IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 50 / 100, // Too low
            amount1: desired.amount1 * 98 / 100  // Acceptable
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            minAmounts,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    // When TWAP is within tick range, minAmount1 must meet threshold
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenMinAmount1TooLow() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP, so both tokens are expected
        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // minAmount1 is too low (50%) while maxSlippage requires 98%
        IUniswapV3Facet.TokenAmounts memory minAmounts = IUniswapV3Facet.TokenAmounts({
            amount0: desired.amount0 * 98 / 100, // Acceptable
            amount1: desired.amount1 * 50 / 100  // Too low
        });

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            minAmounts,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    // Test: Adding liquidity succeeds when spot price matches TWAP (normal conditions)
    function test_addLiquidityUniswapV3_twapProtection_succeedsWhenPriceMatchesTWAP() public {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks(
            _toSpacedTick(initTick - 100),
            _toSpacedTick(initTick + 100)
        );

        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3AddLiquidity(
            _getPool(),
            1117588,
            tick.lower,
            tick.upper,
            1_998_625.137524e6,
            9_935.368650e6,
            10_000.000000e6
        );

        vm.startPrank(allocator);
        ( uint256 tokenId, uint128 liquidity, ) = mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            _minLiquidityPosition(desired.amount0, desired.amount1),
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGt(liquidity, 0, "Should successfully add liquidity");
        assertGt(tokenId, 0, "Should mint position NFT");
    }

    // When twapTick == ticks.upper, _getExpectedAmounts must produce the same
    // amounts that Uniswap V3 pool's _modifyPosition computes at currentTick == tickUpper:
    // amount0 = 0 and amount1 = getAmount1Delta(sqrtLower, sqrtUpper, liquidity) rounded up.
    // The facet reaches this via its "in-range" branch, but the arithmetic collapses
    // to the same values because sqrtTWAPPriceX96 == sqrtRatioUpperX96 at the boundary.
    function test_addLiquidityUniswapV3_twapProtection_boundaryMatchesUniswapV3PoolAtUpperTick() public {
        int24 lowerTick = _toSpacedTick(initTick - 100);
        int24 upperTick = _toSpacedTick(initTick);

        _mockTwapTick(upperTick);

        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Mirror what Uniswap V3 pool's _modifyPosition computes when minting at
        // currentTick == tickUpper (out-of-range above branch):
        //   liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrt, sqrtLower, sqrtUpper, a0, a1)
        //   amount0   = 0
        //   amount1   = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity) // round up
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(upperTick);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtUpper,
            sqrtLower,
            sqrtUpper,
            desired.amount0,
            desired.amount1
        );
        uint256 uniswapAmount1 = UniswapV3Utils.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);

        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks(lowerTick, upperTick);

        // Tighten slippage so min must equal expected exactly.
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(_getPool(), 1e18);

        vm.startPrank(allocator);

        // Any non-zero min.amount0 reverts: facet's expectedAmount0 == 0,
        // matching pool's "amount0 = 0 at the upper boundary".
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            IUniswapV3Facet.TokenAmounts({ amount0: 1, amount1: uniswapAmount1 }),
            block.timestamp + 1 hours
        );

        // min.amount1 one wei below the pool's required amount reverts: facet's
        // expectedAmount1 equals the pool's amount1 exactly (round-up included).
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            tick,
            desired,
            IUniswapV3Facet.TokenAmounts({ amount0: 0, amount1: uniswapAmount1 - 1 }),
            block.timestamp + 1 hours
        );

        vm.stopPrank();
        vm.clearMockedCalls();
    }

}

abstract contract UniswapV3_AddLiquidity_E2ETestBase is UniswapV3_TestBase {

    struct Keys {
        bytes32 aggregateAddLiquidityKey;
        bytes32 token0RateLimitKey;
        bytes32 token1RateLimitKey;
    }

    function _addLiquidityAndValidate(
        uint256                      currentTokenId,
        IUniswapV3Facet.Ticks memory tick,
        uint256                      amount0,
        uint256                      amount1,
        Keys                  memory keys
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        uint256 aggregateAddLiquidityRateLimitBefore = rateLimits.getCurrentRateLimit(keys.aggregateAddLiquidityKey);
        uint256 token0RateLimitBefore                = rateLimits.getCurrentRateLimit(keys.token0RateLimitKey);
        uint256 token1RateLimitBefore                = rateLimits.getCurrentRateLimit(keys.token1RateLimitKey);

        (tokenId, liquidity, amount0Used, amount1Used) = _addLiquidity(
            currentTokenId,
            tick,
            IUniswapV3Facet.TokenAmounts(amount0, amount1),
            _minLiquidityPosition(amount0, amount1)
        );

        uint256 aggregateAddLiquidityRateLimitAfter = rateLimits.getCurrentRateLimit(keys.aggregateAddLiquidityKey);
        uint256 token0RateLimitAfter                = rateLimits.getCurrentRateLimit(keys.token0RateLimitKey);
        uint256 token1RateLimitAfter                = rateLimits.getCurrentRateLimit(keys.token1RateLimitKey);

        uint256 normalizedAmount0Used = amount0Used * 1e18 / 10 ** token0.decimals();
        uint256 normalizedAmount1Used = amount1Used * 1e18 / 10 ** token1.decimals();

        assertApproxEqAbs(
            aggregateAddLiquidityRateLimitBefore - aggregateAddLiquidityRateLimitAfter,
            normalizedAmount0Used + normalizedAmount1Used,
            1,
            "aggregate rate limit delta mismatch"
        );

        assertEq(token0RateLimitBefore - token0RateLimitAfter, amount0Used, "token0 rate limit delta mismatch");
        assertEq(token1RateLimitBefore - token1RateLimitAfter, amount1Used, "token1 rate limit delta mismatch");
    }

    function _e2eAddLiquidityUniswapV3(
        uint256        addAmount0,
        uint256        addAmount1,
        int24          lowerTickDelta,
        int24          upperTickDelta,
        Keys    memory keys
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        uint256 amount0 = addAmount0;
        uint256 amount1 = addAmount1;

        deal(address(token0), address(almProxy), amount0);
        deal(address(token1), address(almProxy), amount1);

        IUniswapV3Facet.Ticks memory tick = IUniswapV3Facet.Ticks(
            _toSpacedTick(initTick + lowerTickDelta),
            _toSpacedTick(initTick + upperTickDelta)
        );

        (tokenId, liquidity, amount0Used, amount1Used) = _addLiquidityAndValidate(
            0,
            tick,
            amount0,
            amount1,
            keys
        );

        assertGt(liquidity, 0, "liquidity should be greater than 0");

        assertApproxEqRel(amount0, amount0Used, .05e18, "amount0Used should be within 5% of amount0");
        assertEq(amount1, amount1Used, "amount1Used should be within .05% of amount1");

        vm.warp(block.timestamp + 2 hours); // Advance sufficient time for twap

        amount0 *= 2;
        amount1 *= 2;

        deal(address(token0), address(almProxy), amount0);
        deal(address(token1), address(almProxy), amount1);

        (/* uint256 tokenId */, liquidity, amount0Used, amount1Used) = _addLiquidityAndValidate(
            tokenId,
            tick,
            amount0,
            amount1,
            keys
        );

        assertGt(liquidity, 0, "liquidity should be greater than 0");

        assertApproxEqRel(amount0, amount0Used, .05e18, "amount0Used should be within 5% of amount0");
        assertEq(amount1, amount1Used, "amount1Used should be within .05% of amount1");
    }

}

contract MainnetController_UniswapV3_AddLiquidity_DAIUSDC_E2ETests is UniswapV3_AddLiquidity_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function _getKeys() internal view returns (Keys memory) {
        return Keys({
            aggregateAddLiquidityKey: uniswapV3_DaiUsdcPool_AggregateAddLiquidityKey,
            token0RateLimitKey:       uniswapV3_DaiUsdcPool_DaiAddLiquidityKey,
            token1RateLimitKey:       uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey
        });
    }

    function test_e2e_addLiquidityUniswapV3_equalParts(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        // Pool is slightly overweight DAI, so reduce USDC amount to counteract
        addAmount1 = addAmount1 * 93 / 100;

        _e2eAddLiquidityUniswapV3(
            addAmount0,
            addAmount1,
            -100,
            100,
            _getKeys()
        );
    }

    function test_e2e_addLiquidityUniswapV3_token0Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;

        _e2eAddLiquidityUniswapV3(
            addAmount0,
            0,
            50,
            100,
            _getKeys()
        );
    }

    function test_e2e_addLiquidityUniswapV3_token1Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2eAddLiquidityUniswapV3(
            0,
            addAmount1,
            -100,
            -50,
            _getKeys()
        );
    }

}

contract MainnetController_UniswapV3_AddLiquidity_USDCUSDT_E2ETests is UniswapV3_AddLiquidity_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function _getKeys() internal view returns (Keys memory) {
        return Keys({
            aggregateAddLiquidityKey: uniswapV3_UsdcUsdtPool_AggregateAddLiquidityKey,
            token0RateLimitKey:       uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey,
            token1RateLimitKey:       uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey
        });
    }

    function test_e2e_addLiquidityUniswapV3_equalParts(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2eAddLiquidityUniswapV3(
            addAmount0,
            addAmount1,
            -100,
            100,
            _getKeys()
        );
    }

    function test_e2e_addLiquidityUniswapV3_token0Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;

        _e2eAddLiquidityUniswapV3(
            addAmount0,
            0,
            50,
            100,
            _getKeys()
        );
    }

    function test_e2e_addLiquidityUniswapV3_token1Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2eAddLiquidityUniswapV3(
            0,
            addAmount1,
            -100,
            -50,
            _getKeys()
        );
    }

}

contract MainnetController_UniswapV3_RemoveLiquidity_FailureTests is UniswapV3_TestBase {

    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;

    uint256 defaultMinAmount0;
    uint256 defaultMinAmount1;

    function setUp() public override {
        super.setUp();

        (tokenId, liquidity, amount0, amount1) = _mintProxyPosition();

        defaultMinAmount0 = amount0 * 98 / 100;
        defaultMinAmount1 = amount1 * 98 / 100;
    }

    function _defaultTickRange() internal view returns (IUniswapV3Facet.Ticks memory) {
        return IUniswapV3Facet.Ticks({ lower: _toSpacedTick(initTick - 50), upper: _toSpacedTick(initTick + 50) });
    }

    function _defaultDesiredPosition() internal view returns (IUniswapV3Facet.TokenAmounts memory) {
        uint256 desiredAmount0 = 1_000 * 10 ** uint256(token0Decimals);
        uint8 decimals1 = IERC20(address(token1)).decimals();
        uint256 desiredAmount1 = 1_000 * 10 ** uint256(decimals1);

        return IUniswapV3Facet.TokenAmounts({ amount0: desiredAmount0, amount1: desiredAmount1 });
    }

    function _mintProxyPosition() internal returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();
        IUniswapV3Facet.Ticks memory tick = _defaultTickRange();

        deal(address(token0), address(almProxy), desired.amount0);
        deal(address(token1), address(almProxy), desired.amount1);

        vm.startPrank(address(almProxy));
        SafeERC20.forceApprove(IERC20OZ(address(token0)), UNISWAP_V3_POSITION_MANAGER, desired.amount0);
        SafeERC20.forceApprove(IERC20OZ(address(token1)), UNISWAP_V3_POSITION_MANAGER, desired.amount1);

        (tokenId_, liquidity_, amount0_, amount1_) = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: poolFee,
                tickLower: _toSpacedTick(tick.lower),
                tickUpper: _toSpacedTick(tick.upper),
                amount0Desired: desired.amount0,
                amount1Desired: desired.amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(almProxy),
                deadline: block.timestamp + 1 hours
            })
        );
        vm.stopPrank();
    }

    function _mintExternalPosition() internal returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        IUniswapV3Facet.TokenAmounts memory desired = _defaultDesiredPosition();

        deal(address(token0), stranger, desired.amount0);
        deal(address(token1), stranger, desired.amount1);

        vm.startPrank(stranger);
        SafeERC20.forceApprove(IERC20OZ(address(token0)), UNISWAP_V3_POSITION_MANAGER, desired.amount0);
        SafeERC20.forceApprove(IERC20OZ(address(token1)), UNISWAP_V3_POSITION_MANAGER, desired.amount1);

        (tokenId_, liquidity_, amount0_, amount1_) = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: poolFee,
                tickLower: _toSpacedTick(initTick - 50),
                tickUpper: _toSpacedTick(initTick + 50),
                amount0Desired: desired.amount0,
                amount1Desired: desired.amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: stranger,
                deadline: block.timestamp + 1 hours
            })
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_reentrancy() public {
        _setControllerEntered();

        vm.startPrank(allocator);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: 0, amount1: 0 }),
            block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_notAllocator() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                ALLOCATOR_ROLE
            )
        );

        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            0,
            1,
            IUniswapV3Facet.TokenAmounts({ amount0: 0, amount1: 0 }),
            block.timestamp + 1 hours
        );
    }

    function test_removeLiquidityUniswapV3_maxSlippageNotSet() public {
        ( uint256 externalTokenId, uint128 externalLiquidity, , ) = _mintExternalPosition();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(_getPool(), 0);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/max-slippage-not-set");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            externalTokenId,
            externalLiquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_proxyDoesNotOwnTokenId() public {
        (uint256 externalTokenId, uint128 externalLiquidity,,) = _mintExternalPosition();

        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/proxy-does-not-own-token-id");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            externalTokenId,
            externalLiquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_zeroLiquidity() public {
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/liquidity-oob");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            0,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_liquidityTooHigh() public {
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/liquidity-oob");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            type(uint128).max,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_invalidPosition() public {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUniswapV3MaxSlippage(UNISWAP_V3_DAI_USDC_POOL, 1_000_000e18);

        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/invalid-pool");
        mainnetController.removeLiquidityUniswapV3(
            UNISWAP_V3_DAI_USDC_POOL,
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_rateLimitExceeded() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_RemoveLiquidityKey, 1, 0);
        vm.stopPrank();

        vm.startPrank(allocator);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_minAmount0BelowBound() public {
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: 0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_minAmount1BelowBound() public {
        vm.startPrank(allocator);
        vm.expectRevert("UniswapV3Facet/min-amount-below-bound");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: defaultMinAmount0, amount1: 0 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

}

abstract contract UniswapV3_RemoveLiquidity_E2ETestBase is UniswapV3_TestBase {

    uint256 tokenId;
    uint128 totalLiquidity;
    uint256 amount0Added;
    uint256 amount1Added;

    function setUp() public override {
        super.setUp();

        _defaultAddLiquidity();
    }

    function _defaultAddLiquidity() internal virtual {
        uint256 addAmount = 1_000_000e18;

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        (tokenId, totalLiquidity, amount0Added, amount1Added) = _addLiquidity(
            addAmount0,
            addAmount1,
            IUniswapV3Facet.Ticks(-100, 100)
        );
    }

    function _addLiquidity(uint256 addAmount0, uint256 addAmount1, IUniswapV3Facet.Ticks memory addTickDelta)
        internal
        returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0Used, uint256 amount1Used)
    {
        deal(address(token0), address(almProxy), addAmount0);
        deal(address(token1), address(almProxy), addAmount1);

        (tokenId_, liquidity_, amount0Used, amount1Used) = _addLiquidity(
            0,
            IUniswapV3Facet.Ticks(
                _toSpacedTick(initTick + addTickDelta.lower),
                _toSpacedTick(initTick + addTickDelta.upper)
            ),
            IUniswapV3Facet.TokenAmounts(addAmount0, addAmount1),
            _minLiquidityPosition(addAmount0, addAmount1)
        );

        vm.warp(block.timestamp + 2 hours); // Advance sufficient time for twap
    }

    function _removeLiquidityAndValidate(
        uint256 tokenId_,
        uint128 liquidity_,
        uint256 minAmount0,
        uint256 minAmount1,
        bytes32 rateLimitKey
    )
        internal
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        uint256 rateLimitBefore = rateLimits.getCurrentRateLimit(rateLimitKey);

        vm.startPrank(allocator);
        IUniswapV3Facet.TokenAmounts memory amountsUsed = mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId_,
            liquidity_,
            IUniswapV3Facet.TokenAmounts(minAmount0, minAmount1),
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        amount0Used = amountsUsed.amount0;
        amount1Used = amountsUsed.amount1;

        assertGe(amount0Used, minAmount0, "amount0Used should be greater than or equal to minAmount0");
        assertGe(amount1Used, minAmount1, "amount1Used should be greater than or equal to minAmount1");

        assertApproxEqRel(
            amount0Used,
            amount0Added * liquidity_ / totalLiquidity,
            0.0001e18,
            "amount0Used should be within 0.01% of amount0Added * liquidity / totalLiquidity"
        );

        assertApproxEqRel(
            amount1Used,
            amount1Added * liquidity_ / totalLiquidity,
            0.0001e18,
            "amount1Used should be within 0.01% of amount1Added * liquidity / totalLiquidity"
        );

        uint256 rateLimitAfter = rateLimits.getCurrentRateLimit(rateLimitKey);

        uint256 normalizedAmount0Used = amount0Used * 1e18 / 10 ** token0.decimals();
        uint256 normalizedAmount1Used = amount1Used * 1e18 / 10 ** token1.decimals();

        assertApproxEqAbs(
            rateLimitBefore - rateLimitAfter,
            normalizedAmount0Used + normalizedAmount1Used,
            1,
            "rate limit delta mismatch"
        );
    }

}

contract MainnetController_UniswapV3_RemoveLiquidity_DAIUSDC_E2ETests is UniswapV3_RemoveLiquidity_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function _defaultAddLiquidity() internal override virtual {
        uint256 addAmount = 1_000_000e18;

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        // Pool is slightly overweight DAI
        addAmount1 = addAmount1 * 93 / 100;

        (tokenId, totalLiquidity, amount0Added, amount1Added) = _addLiquidity(
            addAmount0,
            addAmount1,
            IUniswapV3Facet.Ticks(-100, 100)
        );
    }

    function test_e2e_addRemoveLiquidityUniswapV3_daiUsdc(uint128 liquidity) public {
        liquidity = uint128(bound(uint256(liquidity), 1000000, uint256(totalLiquidity)));

        uint256 minAmount0 = amount0Added * liquidity / totalLiquidity;
        uint256 minAmount1 = amount1Added * liquidity / totalLiquidity;

        _removeLiquidityAndValidate(
            tokenId,
            liquidity,
            minAmount0 * 9999/10000,
            minAmount1 * 9999/10000,
            uniswapV3_DaiUsdcPool_RemoveLiquidityKey
        );
    }

    function test_e2e_removeLiquidityUniswapV3_daiUsdc_allLiquidity() public {
        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3RemoveLiquidity(
            _getPool(),
            1117588,
            192838924760199336527,
            993472.837339547954822405e18,
            929999.999999e6
        );

        _removeLiquidityAndValidate(
            tokenId,
            totalLiquidity,
            amount0Added * 9999/10000,
            amount1Added * 9999/10000,
            uniswapV3_DaiUsdcPool_RemoveLiquidityKey
        );
    }

}

contract MainnetController_UniswapV3_RemoveLiquidity_USDCUSDT_E2ETests is UniswapV3_RemoveLiquidity_E2ETestBase {

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function test_e2e_addRemoveLiquidityUniswapV3_usdcUsdt(uint128 liquidity) public {
        liquidity = uint128(bound(uint256(liquidity), 1000000, uint256(totalLiquidity)));

        uint256 minAmount0 = amount0Added * liquidity / totalLiquidity;
        uint256 minAmount1 = amount1Added * liquidity / totalLiquidity;

        _removeLiquidityAndValidate(
            tokenId,
            liquidity,
            minAmount0 * 9999/10000,
            minAmount1 * 9999/10000,
            uniswapV3_UsdcUsdtPool_RemoveLiquidityKey
        );
    }

    function test_e2e_removeLiquidityUniswapV3_usdcUsdt_allLiquidity() public {
        vm.expectEmit(address(mainnetController));
        emit IUniswapV3Facet.UniswapV3RemoveLiquidity(
            _getPool(),
            1117588,
            199862513752444,
            993536.864930e6,
            999999.999999e6
        );

        _removeLiquidityAndValidate(
            tokenId,
            totalLiquidity,
            amount0Added * 9999/10000,
            amount1Added * 9999/10000,
            uniswapV3_UsdcUsdtPool_RemoveLiquidityKey
        );
    }

}

// Adapted from Certora's findings: https://gist.github.com/3docSec/616413000a6ebb154211db74589e0782
contract MainnetController_UniswapV3_Swap_SandwichAttackTest is UniswapV3_TestBase {

    function setUp() public override {
        super.setUp();
    }

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22181045; // Apr 02, 2025
    }

    function test_uniswapV3_sandwichRisk_withoutTWAP() public {
        address pool                    = _getPool();
        IUniswapV3PoolLike poolContract = IUniswapV3PoolLike(pool);
        uint24 fee                      = poolContract.fee();

        // Victim intends to swap 1M USDC -> DAI via the controller.
        uint256 victimAmountIn = 1_000_000e6;

        // Configure rate limits and Uniswap params for this pool.
        bytes32 swapKey = mainnetController.getUniswapV3SwapRateLimitKey(pool, address(usdc));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(swapKey);
        // Allow up to ~1% local slippage
        mainnetController.setUniswapV3MaxSlippage(pool, 0.99e18);
        // Allow a moderate max tick move per swap.
        mainnetController.setUniswapV3PoolMaxTickDelta(pool, 500);
        vm.stopPrank();

        // Front-run leg: USDC -> DAI in the same direction as the forthcoming victim swap.
        uint256 attackerInitialUsdc = 10_000_000e6;
        deal(address(usdc), address(this), attackerInitialUsdc);
        IERC20(address(usdc)).approve(UNISWAP_V3_ROUTER, attackerInitialUsdc);

        ISwapRouter.ExactInputSingleParams memory frontParams = ISwapRouter.ExactInputSingleParams({
            tokenIn           : address(usdc),
            tokenOut          : address(dai),
            fee               : fee,
            recipient         : address(this),
            amountIn          : attackerInitialUsdc,
            amountOutMinimum  : 0,
            sqrtPriceLimitX96 : 0
        });

        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(frontParams);

        // Victim swap via the controller at the manipulated spot price (USDC -> DAI).
        deal(address(usdc), address(almProxy), victimAmountIn);

        uint256 victimDaiBalanceBefore = dai.balanceOf(address(almProxy));

        vm.startPrank(allocator);
        uint256[] memory minAmountOut = new uint256[](8);

        minAmountOut[0] = 5.2e13;
        minAmountOut[1] = 5.1e13;
        minAmountOut[2] = 4.95e13;
        minAmountOut[3] = 4.82e13;
        minAmountOut[4] = 4.70e13;
        minAmountOut[5] = 4.60e13;
        minAmountOut[6] = 4.48e13;
        minAmountOut[7] = 3.69e13;

        for (uint256 i = 0; i < 1; i++) {
            uint256 amountIn = usdc.balanceOf(address(almProxy));

            // This should be triggered since we calculate `sqrtPriceLimitX96` using the TWAP
            vm.expectRevert(bytes("SPL"));
            mainnetController.swapUniswapV3(
                pool,
                address(usdc),
                amountIn,
                minAmountOut[i],
                500
            );
        }
        vm.stopPrank();

        // Back-run leg: attacker sells all received DAI back to USDC after victim restores price.
        uint256 attackerDaiBalance = dai.balanceOf(address(this));
        IERC20(address(dai)).approve(UNISWAP_V3_ROUTER, attackerDaiBalance);

        ISwapRouter.ExactInputSingleParams memory backParams = ISwapRouter.ExactInputSingleParams({
            tokenIn           : address(dai),
            tokenOut          : address(usdc),
            fee               : fee,
            recipient         : address(this),
            amountIn          : attackerDaiBalance,
            amountOutMinimum  : 0,
            sqrtPriceLimitX96 : 0
        });

        ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(backParams);

        uint256 attackerFinalUsdc = usdc.balanceOf(address(this));

        assertLe(
            attackerFinalUsdc,
            attackerInitialUsdc,
            "attacker should have lower or same balance of USDC as before attack"
        );

        assertEq(
            victimAmountIn,
            usdc.balanceOf(address(almProxy)),
            "proxy should have same balance of USDC as before attack"
        );

        assertEq(
            dai.balanceOf(address(almProxy)),
            victimDaiBalanceBefore,
            "proxy should have same balance of DAI as before attack"
        );
    }

}
