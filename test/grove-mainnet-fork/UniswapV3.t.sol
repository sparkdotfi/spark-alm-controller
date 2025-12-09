// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IERC20Metadata }     from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 as IERC20OZ } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }          from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { INonfungiblePositionManager, IUniswapV3PoolLike } from "../../src/libraries/UniswapV3Lib.sol";
import { UniswapV3Lib }                                    from "../../src/libraries/UniswapV3Lib.sol";

import { ISwapRouter } from "../../src/interfaces/UniswapV3Interfaces.sol";

import { UniV3Utils } from "lib/dss-allocator/test/funnels/UniV3Utils.sol";
import { FullMath }   from "lib/dss-allocator/src/funnels/uniV3/FullMath.sol";
import { TickMath }   from "lib/dss-allocator/src/funnels/uniV3/TickMath.sol";

interface IUniswapV3PoolLikeTickSpacing is IUniswapV3PoolLike {
    function tickSpacing() external view returns (int24);
}

contract UniswapV3TestBase is ForkTestBase {
    address constant UNISWAP_V3_USDC_USDT_POOL   = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address constant UNISWAP_V3_DAI_USDC_POOL    = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;

    int24 internal constant DEFAULT_TICK_LOWER = -600;
    int24 internal constant DEFAULT_TICK_UPPER =  600;

    bytes32 uniswapV3_UsdcUsdtPool_UsdcSwapKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdtSwapKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey;
    bytes32 uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey;

    bytes32 uniswapV3_DaiUsdcPool_DaiSwapKey;
    bytes32 uniswapV3_DaiUsdcPool_UsdcSwapKey;
    bytes32 uniswapV3_DaiUsdcPool_DaiAddLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_DaiRemoveLiquidityKey;
    bytes32 uniswapV3_DaiUsdcPool_UsdcRemoveLiquidityKey;

    IUniswapV3PoolLike internal pool;
    IERC20             internal token0;
    IERC20             internal token1;
    uint24             internal poolFee;
    uint8              internal token0Decimals;
    int24              internal initTick;
    int24              internal tickSpacing;

    function setUp() public virtual override  {
        super.setUp();

        uniswapV3_UsdcUsdtPool_UsdcSwapKey            = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_SWAP(),     address(usdc), UNISWAP_V3_USDC_USDT_POOL);
        uniswapV3_UsdcUsdtPool_UsdtSwapKey            = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_SWAP(),     address(usdt), UNISWAP_V3_USDC_USDT_POOL);
        uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey    = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_DEPOSIT(),  address(usdc), UNISWAP_V3_USDC_USDT_POOL);
        uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey    = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_DEPOSIT(),  address(usdt), UNISWAP_V3_USDC_USDT_POOL);
        uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_WITHDRAW(), address(usdc), UNISWAP_V3_USDC_USDT_POOL);
        uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_WITHDRAW(), address(usdt), UNISWAP_V3_USDC_USDT_POOL);

        uniswapV3_DaiUsdcPool_DaiSwapKey             = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_SWAP(),     address(dai),  UNISWAP_V3_DAI_USDC_POOL);
        uniswapV3_DaiUsdcPool_UsdcSwapKey            = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_SWAP(),     address(usdc), UNISWAP_V3_DAI_USDC_POOL);
        uniswapV3_DaiUsdcPool_DaiAddLiquidityKey     = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_DEPOSIT(),  address(dai),  UNISWAP_V3_DAI_USDC_POOL);
        uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey    = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_DEPOSIT(),  address(usdc), UNISWAP_V3_DAI_USDC_POOL);
        uniswapV3_DaiUsdcPool_DaiRemoveLiquidityKey  = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_WITHDRAW(), address(dai),  UNISWAP_V3_DAI_USDC_POOL);
        uniswapV3_DaiUsdcPool_UsdcRemoveLiquidityKey = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_WITHDRAW(), address(usdc), UNISWAP_V3_DAI_USDC_POOL);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcSwapKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtSwapKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_DaiSwapKey,   1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_UsdcSwapKey,  1_000_000e6,  uint256(1_000_000e6)  / 1 days);

        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_DaiAddLiquidityKey,   1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey,  1_000_000e6,  uint256(1_000_000e6)  / 1 days);

        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey, 1_000_000e6,  uint256(1_000_000e6)  / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_DaiRemoveLiquidityKey,   1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(uniswapV3_DaiUsdcPool_UsdcRemoveLiquidityKey,  1_000_000e6,  uint256(1_000_000e6)  / 1 days);

        // Set a higher slippage to allow for successes
        mainnetController.setMaxSlippage(_getPool(), 0.98e18);
        // All trades must have no more than 200 ticks impact on the pool. For most stablecoin pools, a tick is 1bps
        mainnetController.setUniswapV3PoolMaxTickDelta(_getPool(), 200);
        mainnetController.setUniswapV3TwapSecondsAgo(_getPool(),   1 days);

        vm.stopPrank();

        pool               = IUniswapV3PoolLike(_getPool());
        token0             = IERC20(pool.token0());
        token1             = IERC20(pool.token1());
        poolFee            = pool.fee();
        token0Decimals     = IERC20Metadata(address(token0)).decimals();
        (, initTick, ,,,,) = pool.slot0();
        tickSpacing        = IUniswapV3PoolLikeTickSpacing(address(pool)).tickSpacing();

        vm.startPrank(GROVE_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick - 1000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick + 1000);
        vm.stopPrank();
    }


    function _getSwapKey(address tokenIn) internal view returns (bytes32) {
        return RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_UNISWAP_V3_SWAP(), tokenIn, _getPool());
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
        vm.startPrank(relayer);
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

    function _addLiquidity(uint256 _tokenId, UniswapV3Lib.Tick memory _tick, UniswapV3Lib.TokenAmounts memory _desired, UniswapV3Lib.TokenAmounts memory _min) internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        vm.startPrank(relayer);
        (tokenId, liquidity, amount0Used, amount1Used)
            = mainnetController.addLiquidityUniswapV3(
                _getPool(),
                _tokenId,
                _tick,
                _desired,
                _min,
                block.timestamp + 1 hours
            );
        vm.stopPrank();
    }

    function _minLiquidityPosition(uint256 amount0, uint256 amount1) internal pure returns (UniswapV3Lib.TokenAmounts memory) {
        return UniswapV3Lib.TokenAmounts({
            amount0 : amount0 * 98 / 100,
            amount1 : amount1 * 98 / 100
        });
    }
}

contract MainnetControllerConfigFailureTests is UniswapV3TestBase {
    int24 internal constant MIN_UNISWAP_TICK = -887_272;
    int24 internal constant MAX_UNISWAP_TICK =  887_272;

    function test_setUniswapV3PoolMaxTickDelta_isZero() public {
        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/max-tick-delta-out-of-bounds");
        mainnetController.setUniswapV3PoolMaxTickDelta(_getPool(), 0);
    }

    function test_setUniswapV3PoolMaxTickDelta_isTooLarge() public {
        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/max-tick-delta-out-of-bounds");
        mainnetController.setUniswapV3PoolMaxTickDelta(_getPool(), UniswapV3Lib.MAX_TICK_DELTA + 1);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_isTooSmall() public {
        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/lower-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), MIN_UNISWAP_TICK - 1);
    }


    function test_setUniswapv3AddLiquidityLowerTickBound_isTooLarge() public {
        (, UniswapV3Lib.Tick memory tickBounds, ) = mainnetController.uniswapV3PoolParams(_getPool());
        int24 currentUpper = tickBounds.upper;

        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/lower-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), currentUpper);
    }

    function test_setUniswapv3AddLiquidityUpperTickBound_isTooSmall() public {
        (, UniswapV3Lib.Tick memory tickBounds, ) = mainnetController.uniswapV3PoolParams(_getPool());
        int24 currentLower = tickBounds.lower;

        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/upper-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), currentLower);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_isTooLarge() public {
        vm.prank(GROVE_PROXY);
        vm.expectRevert("MainnetController/upper-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), MAX_UNISWAP_TICK + 1);
    }
}

contract MainnetControllerSwapUniswapV3FailureTests is UniswapV3TestBase {

    function test_swapUniswapV3_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            1,
            1,
            100
        );
    }

    function test_swapUniswapV3_maxSlippageNotSet() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.prank(GROVE_PROXY);
        mainnetController.setMaxSlippage(_getPool(), 0);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/max-slippage-not-set");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            200
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_invalidTokenIn() public {
        uint256 amountIn = 100_000e6;
        deal(address(dai), address(almProxy), amountIn);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/invalid-token-pair");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(dai),
            amountIn,
            0,
            200
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_slippageTooHigh() public {
        uint256 amountIn = 150_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(relayer);
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

    function test_swapUniswapV3_invalidMaxTickDelta() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/invalid-max-tick-delta");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            type(uint24).max
        );
        vm.stopPrank();
    }

    function test_swapUniswapV3_limitsAmountOutWhenCrossingMaxTick() public {
        uint256 amountIn = 2_000_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(token0)), 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        vm.startPrank(relayer);
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

    function test_swapUniswapV3_minAmountNotMet() public {
        uint256 amountIn = 100_000e6;
        _fundProxy(amountIn, 0);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-not-met");
        mainnetController.swapUniswapV3(
            _getPool(),
            address(token0),
            amountIn,
            0,
            200
        );
        vm.stopPrank();
    }
}

contract MainnetControllerSwapUniswapV3SuccessTests is UniswapV3TestBase {

    function test_swapUniswapV3_token0ToToken1() public {
        uint256 amountIn = 250_000e6;
        _fundProxy(amountIn, 0);

        uint256 swapLimitBefore     = rateLimits.getCurrentRateLimit(_getSwapKey(address(token0)));
        uint256 token0BalanceBefore = token0.balanceOf(address(almProxy));
        uint256 token1BalanceBefore = token1.balanceOf(address(almProxy));

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
}


contract MainnetControllerE2EUniswapV3Test is UniswapV3TestBase {
    function _e2e_swapUniswapV3(uint256 swapAmount, IERC20 tokenIn, IERC20 tokenOut, bytes32 swapKey) internal {
        deal(address(tokenIn), address(almProxy), swapAmount);

        uint8 tokenInDecimals  = IERC20Metadata(address(tokenIn)).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(address(tokenOut)).decimals();

        uint256 swapAmountOut = FullMath.mulDiv(swapAmount, 10**tokenOutDecimals, 10**tokenInDecimals);

        uint256 tokenOutBalanceBeforeSwap = tokenOut.balanceOf(address(almProxy));

        uint256 swapRateLimitBefore = rateLimits.getCurrentRateLimit(swapKey);

        vm.startPrank(relayer);
        uint256 amountOut = mainnetController.swapUniswapV3(
            _getPool(),
            address(tokenIn),
            swapAmount,
            swapAmountOut * 999 / 1000,
            200 // allow for price impact of up to 2 points
        );
        vm.stopPrank();

        uint256 normalizedAmountOut = FullMath.mulDiv(amountOut, 10**tokenInDecimals, 10**tokenOutDecimals);

        assertApproxEqRel(normalizedAmountOut, swapAmount, .005e18, "normalizedAmountOut should be within 0.05% of swapAmount");
        assertEq(tokenIn.balanceOf(address(almProxy)), 0, "tokenIn balance of almProxy should be 0");
        assertEq(tokenOut.balanceOf(address(almProxy)), tokenOutBalanceBeforeSwap + amountOut, "tokenOut balance of almProxy should be equal to tokenOutBalanceBeforeSwap + amountOut");
        assertEq(rateLimits.getCurrentRateLimit(swapKey), swapRateLimitBefore - swapAmount, "swap rate limit should be equal to swapRateLimitBefore - swapAmount");
    }
}

contract MainnetControllerE2EUniswapV3DaiUsdcTest is MainnetControllerE2EUniswapV3Test {
    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function test_e2e_swapUniswapV3_daiToUsdc(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1_000_000e18);

        _e2e_swapUniswapV3(swapAmount, dai, usdc, _getSwapKey(address(dai)));
    }

    function test_e2e_swapUniswapV3_daiToUsdc_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e18, 2_000_000e18);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(dai)), 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        _e2e_swapUniswapV3(swapAmount, dai, usdc, _getSwapKey(address(dai)));
    }


    function test_e2e_swapUniswapV3_usdcToDai(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2e_swapUniswapV3(swapAmount, usdc, dai, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_usdcToDai_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 2_000_000e6);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdc)), 2_000_000e6, uint256(2_000_000e6) / 1 days);
        vm.stopPrank();

        _e2e_swapUniswapV3(swapAmount, usdc, dai, _getSwapKey(address(usdc)));
    }
}

contract MainnetControllerE2EUniswapV3UsdcUsdtPoolTest is MainnetControllerE2EUniswapV3Test {
    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function test_e2e_swapUniswapV3_usdcToUsdt(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2e_swapUniswapV3(swapAmount, usdc, usdt, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_usdcToUsdt_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 5_000_000e6);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdc)), 5_000_000e6, uint256(5_000_000e6) / 1 days);
        vm.stopPrank();

        _e2e_swapUniswapV3(swapAmount, usdc, usdt, _getSwapKey(address(usdc)));
    }

    function test_e2e_swapUniswapV3_usdtToUsdc(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e6, 1_000_000e6);

        _e2e_swapUniswapV3(swapAmount, usdt, usdc, _getSwapKey(address(usdt)));
    }

    function test_e2e_swapUniswapV3_usdtToUsdc_large(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1_000_000e6, 5_000_000e6);

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(_getSwapKey(address(usdt)), 5_000_000e6, uint256(5_000_000e6) / 1 days);
        vm.stopPrank();

        _e2e_swapUniswapV3(swapAmount, usdt, usdc, _getSwapKey(address(usdt)));
    }
}

contract MainnetControllerAddLiquidityFailureTests is UniswapV3TestBase {

    function _defaultTickRange() internal view returns (UniswapV3Lib.Tick memory) {
        return UniswapV3Lib.Tick({ lower: _toSpacedTick(initTick - 100), upper: _toSpacedTick(initTick + 100) });
    }

    function _defaultDesiredPosition() internal view returns (UniswapV3Lib.TokenAmounts memory) {
        uint256 amount0 = 1000 * 10 ** uint256(token0Decimals);
        uint256 amount1 = 1000 * 10 ** uint256(IERC20Metadata(address(token1)).decimals());

        return UniswapV3Lib.TokenAmounts({ amount0: amount0, amount1: amount1 });
    }

    function _defaultMinPosition(UniswapV3Lib.TokenAmounts memory desired) internal pure returns (UniswapV3Lib.TokenAmounts memory) {
        return UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 99 / 100,
            amount1: desired.amount1 * 99 / 100
        });
    }

    function _prepareDefaultAddLiquidity()
        internal
        returns (
            UniswapV3Lib.Tick memory tick,
            UniswapV3Lib.TokenAmounts memory desired,
            UniswapV3Lib.TokenAmounts memory min
        )
    {
        tick = _defaultTickRange();
        desired = _defaultDesiredPosition();
        min = _defaultMinPosition(desired);
        _fundProxy(desired.amount0, desired.amount1);
    }

    function _buildMintParams(
        UniswapV3Lib.Tick         memory tick,
        UniswapV3Lib.TokenAmounts memory desired,
        UniswapV3Lib.TokenAmounts memory min,
        uint256                   deadline
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
        address stranger = makeAddr("stranger-lp");
        uint256 amount0 = 5 * 10 ** uint256(token0Decimals);
        uint8 token1Decimals = IERC20Metadata(address(token1)).decimals();
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

    function test_addLiquidityUniswapV3_notRelayer() public {
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                RELAYER
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        uint256 deadline = block.timestamp + 1 hours;
        INonfungiblePositionManager.MintParams memory mintParams = _buildMintParams(tick, desired, min, deadline);

        vm.mockCall(
            UNISWAP_V3_POSITION_MANAGER,
            abi.encodeCall(INonfungiblePositionManager.mint, (mintParams)),
            abi.encode(uint256(1), uint128(0), uint256(0), uint256(0))
        );

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/no-liquidity-increased");
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
        UniswapV3Lib.Tick memory tick = _defaultTickRange();
        UniswapV3Lib.TokenAmounts memory zeroPosition = UniswapV3Lib.TokenAmounts({
            amount0: 0,
            amount1: 0
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/zero-amount");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        vm.prank(GROVE_PROXY);
        mainnetController.setMaxSlippage(_getPool(), 0);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/max-slippage-not-set");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();
        tick.lower = initTick - 2000;

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/invalid-tick-lower");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();
        tick.upper = initTick + 2000;

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/invalid-tick-upper");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired,) = _prepareDefaultAddLiquidity();
        UniswapV3Lib.TokenAmounts memory min = UniswapV3Lib.TokenAmounts({
            amount0: 0,
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired,) = _prepareDefaultAddLiquidity();
        UniswapV3Lib.TokenAmounts memory min = UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: 0
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/proxy-does-not-own-token-id");
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

    function test_addLiquidityUniswapV3_existingPosition_positionsCallFails() public {
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        uint256 tokenId = 1234;
        _mockOwnerOf(tokenId);

        vm.mockCallRevert(
            UNISWAP_V3_POSITION_MANAGER,
            abi.encodeCall(INonfungiblePositionManager.positions, (tokenId)),
            abi.encode("fail")
        );

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/positions-call-failed");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        vm.clearMockedCalls();
    }

    function test_addLiquidityUniswapV3_existingPosition_invalidPositionsReturnData() public {
        (UniswapV3Lib.Tick memory tick, UniswapV3Lib.TokenAmounts memory desired, UniswapV3Lib.TokenAmounts memory min)
            = _prepareDefaultAddLiquidity();

        uint256 tokenId = 9999;
        _mockOwnerOf(tokenId);

        vm.mockCall(
            UNISWAP_V3_POSITION_MANAGER,
            abi.encodeCall(INonfungiblePositionManager.positions, (tokenId)),
            abi.encode(uint256(0))
        );

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/invalid-positions-return-data");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            tokenId,
            tick,
            desired,
            min,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        vm.clearMockedCalls();
    }

    function test_addLiquidityUniswapV3_rateLimitExceeded_token0() public {
        uint256 amount0 = 2_000_000e18;
        uint256 amount1 = 0;

        _fundProxy(amount0, amount1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            UniswapV3Lib.Tick({
                lower: _toSpacedTick(initTick+50),
                upper: _toSpacedTick(initTick+100)
            }),
            UniswapV3Lib.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            UniswapV3Lib.TokenAmounts({
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

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityUniswapV3(
            _getPool(),
            0,
            UniswapV3Lib.Tick({
                lower: _toSpacedTick(initTick-100),
                upper: _toSpacedTick(initTick-50)
            }),
            UniswapV3Lib.TokenAmounts({
                amount0: amount0,
                amount1: amount1
            }),
            UniswapV3Lib.TokenAmounts({
                amount0: amount0 * 98 / 100,
                amount1: amount1 * 98 / 100
            }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
}

contract MainnetControllerAddLiquidityTwapProtectionTests is UniswapV3TestBase {

    function _defaultDesiredPosition() internal view returns (UniswapV3Lib.TokenAmounts memory) {
        uint256 amount0 = 10_000 * 10 ** uint256(token0Decimals);
        uint256 amount1 = 10_000 * 10 ** uint256(IERC20Metadata(address(token1)).decimals());

        return UniswapV3Lib.TokenAmounts({ amount0: amount0, amount1: amount1 });
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

    // Transaction fails when spot price has been manipulated out of expected range
    // Even with valid TWAP-based min amounts, Uniswap's own slippage check fails
    // because spot price requires different token ratios than our mins allow
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenSpotPriceManipulated() public {
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP (which is close to spot in normal conditions)
        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // Mock spot price to be way above our tick range (manipulated)
        // At this spot price, Uniswap will want mostly token1, not the balanced amounts we're providing
        _mockSpotTick(tick.upper + 1000);

        // Min amounts are valid per TWAP, but spot price is manipulated
        // Uniswap's mint will fail because actual amounts needed don't match our mins
        UniswapV3Lib.TokenAmounts memory minAmounts = UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(relayer);
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
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenTwapAboveRangeAndMinAmount0NonZero() public {
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Set governance bounds entirely below the current TWAP
        // Pool's TWAP is near initTick, so setting bounds below that puts TWAP above our allowed range
        vm.startPrank(GROVE_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick - 300);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick - 100);
        vm.stopPrank();

        // Relayer uses ticks within governance bounds
        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick - 200),
            upper: _toSpacedTick(initTick - 100)
        });

        // Incorrectly provide non-zero minAmount0 when TWAP expects only token1
        UniswapV3Lib.TokenAmounts memory minAmounts = UniswapV3Lib.TokenAmounts({
            amount0: 1, // Should be 0 when twapTick >= tick.upper
            amount1: desired.amount1 * 98 / 100
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
    function test_addLiquidityUniswapV3_twapProtection_revertsWhenTwapBelowRangeAndMinAmount1NonZero() public {
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Set governance bounds entirely above the current TWAP
        // Pool's TWAP is near initTick, so setting bounds above that puts TWAP below our allowed range
        vm.startPrank(GROVE_PROXY);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_getPool(), initTick + 100);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_getPool(), initTick + 300);
        vm.stopPrank();

        // Relayer uses ticks within governance bounds
        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick + 100),
            upper: _toSpacedTick(initTick + 200)
        });

        // Incorrectly provide non-zero minAmount1 when TWAP expects only token0
        UniswapV3Lib.TokenAmounts memory minAmounts = UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 98 / 100,
            amount1: 1 // Should be 0 when twapTick <= tick.lower
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP, so both tokens are expected
        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // minAmount0 is too low (50%) while maxSlippage requires 98%
        UniswapV3Lib.TokenAmounts memory minAmounts = UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 50 / 100, // Too low
            amount1: desired.amount1 * 98 / 100  // Acceptable
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        // Position range around current TWAP, so both tokens are expected
        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        // minAmount1 is too low (50%) while maxSlippage requires 98%
        UniswapV3Lib.TokenAmounts memory minAmounts = UniswapV3Lib.TokenAmounts({
            amount0: desired.amount0 * 98 / 100, // Acceptable
            amount1: desired.amount1 * 50 / 100  // Too low
        });

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
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
    function test_addLiquidityUniswapV3_twapProtection_succeedsWhenPriceMatchesTwap() public {
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        _fundProxy(desired.amount0, desired.amount1);

        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower: _toSpacedTick(initTick - 100),
            upper: _toSpacedTick(initTick + 100)
        });

        vm.startPrank(relayer);
        (uint256 tokenId, uint128 liquidity,,) = mainnetController.addLiquidityUniswapV3(
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
}

contract MainnetControllerAddLiquidityE2EUniswapV3Test is UniswapV3TestBase {
    function _addLiquidityAndValidate(
        uint256 currentTokenId,
        UniswapV3Lib.Tick memory tick,
        uint256 amount0,
        uint256 amount1,
        bytes32 token0RateLimitKey,
        bytes32 token1RateLimitKey
    )
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        uint256 token0RateLimitBefore = rateLimits.getCurrentRateLimit(token0RateLimitKey);
        uint256 token1RateLimitBefore = rateLimits.getCurrentRateLimit(token1RateLimitKey);

        (tokenId, liquidity, amount0Used, amount1Used) = _addLiquidity(
            currentTokenId,
            tick,
            UniswapV3Lib.TokenAmounts({ amount0: amount0, amount1: amount1 }),
            _minLiquidityPosition(amount0, amount1)
        );

        uint256 token0RateLimitAfter = rateLimits.getCurrentRateLimit(token0RateLimitKey);
        uint256 token1RateLimitAfter = rateLimits.getCurrentRateLimit(token1RateLimitKey);

        assertEq(token0RateLimitBefore - token0RateLimitAfter, amount0Used, "token0 rate limit delta mismatch");
        assertEq(token1RateLimitBefore - token1RateLimitAfter, amount1Used, "token1 rate limit delta mismatch");
    }

    function _e2e_addLiquidityUniswapV3(uint256 addAmount0, uint256 addAmount1, int24 lowerTickDelta, int24 upperTickDelta, bytes32 token0RateLimitKey, bytes32 token1RateLimitKey) internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        uint256 amount0 = addAmount0;
        uint256 amount1 = addAmount1;

        deal(address(token0), address(almProxy), amount0);
        deal(address(token1), address(almProxy), amount1);

        UniswapV3Lib.Tick memory tick = UniswapV3Lib.Tick({
            lower : _toSpacedTick(initTick + lowerTickDelta),
            upper : _toSpacedTick(initTick + upperTickDelta)
        });

        (tokenId, liquidity, amount0Used, amount1Used) = _addLiquidityAndValidate(
            0,
            tick,
            amount0,
            amount1,
            token0RateLimitKey,
            token1RateLimitKey
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
            token0RateLimitKey,
            token1RateLimitKey
        );

        assertGt(liquidity, 0, "liquidity should be greater than 0");

        assertApproxEqRel(amount0, amount0Used, .05e18, "amount0Used should be within 5% of amount0");
        assertEq(amount1, amount1Used, "amount1Used should be within .05% of amount1");
    }
}

contract MainnetControllerAddLiquidityE2EUniswapV3UsdcUsdtTest is MainnetControllerAddLiquidityE2EUniswapV3Test {
    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_USDC_USDT_POOL;
    }

    function test_e2e_addLiquidityUniswapV3_equalParts(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2e_addLiquidityUniswapV3(addAmount0, addAmount1, -100, 100, uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey, uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey);
    }

    function test_e2e_addLiquidityUniswapV3_token0Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;

        _e2e_addLiquidityUniswapV3(addAmount0, 0, 50, 100, uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey, uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey);
    }

    function test_e2e_addLiquidityUniswapV3_token1Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2e_addLiquidityUniswapV3(0, addAmount1, -100, -50, uniswapV3_UsdcUsdtPool_UsdcAddLiquidityKey, uniswapV3_UsdcUsdtPool_UsdtAddLiquidityKey);
    }
}

contract MainnetControllerAddLiquidityE2EUniswapV3DaiUsdcTest is MainnetControllerAddLiquidityE2EUniswapV3Test {
    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
    }

    function test_e2e_addLiquidityUniswapV3_equalParts(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        // Pool is slightly overweight DAI, so reduce USDC amount to counteract
        addAmount1 = addAmount1 * 93 / 100;

        _e2e_addLiquidityUniswapV3(addAmount0, addAmount1, -100, 100, uniswapV3_DaiUsdcPool_DaiAddLiquidityKey, uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey);
    }

    function test_e2e_addLiquidityUniswapV3_token0Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;

        _e2e_addLiquidityUniswapV3(addAmount0, 0, 50, 100, uniswapV3_DaiUsdcPool_DaiAddLiquidityKey, uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey);
    }

    function test_e2e_addLiquidityUniswapV3_token1Only(uint256 addAmount) public {
        addAmount = bound(addAmount, 1e18, 100_000e18);

        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        _e2e_addLiquidityUniswapV3(0, addAmount1, -100, -50, uniswapV3_DaiUsdcPool_DaiAddLiquidityKey, uniswapV3_DaiUsdcPool_UsdcAddLiquidityKey);
    }
}

contract MainnetControllerRemoveLiquidityFailureTests is UniswapV3TestBase {

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

    function _defaultTickRange() internal view returns (UniswapV3Lib.Tick memory) {
        return UniswapV3Lib.Tick({ lower: _toSpacedTick(initTick - 50), upper: _toSpacedTick(initTick + 50) });
    }

    function _defaultDesiredPosition() internal view returns (UniswapV3Lib.TokenAmounts memory) {
        uint256 desiredAmount0 = 1_000 * 10 ** uint256(token0Decimals);
        uint8 decimals1 = IERC20Metadata(address(token1)).decimals();
        uint256 desiredAmount1 = 1_000 * 10 ** uint256(decimals1);

        return UniswapV3Lib.TokenAmounts({ amount0: desiredAmount0, amount1: desiredAmount1 });
    }

    function _mintProxyPosition() internal returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();
        UniswapV3Lib.Tick memory tick = _defaultTickRange();

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
        address stranger = makeAddr("stranger-remove-lp");
        UniswapV3Lib.TokenAmounts memory desired = _defaultDesiredPosition();

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

    function test_removeLiquidityUniswapV3_notRelayer() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                RELAYER
            )
        );

        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            0,
            1,
            UniswapV3Lib.TokenAmounts({ amount0: 0, amount1: 0 }),
            block.timestamp + 1 hours
        );
    }

    function test_removeLiquidityUniswapV3_proxyDoesNotOwnTokenId() public {
        (uint256 externalTokenId, uint128 externalLiquidity,,) = _mintExternalPosition();

        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/proxy-does-not-own-token-id");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            externalTokenId,
            externalLiquidity,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_zeroLiquidity() public {
        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/liquidity-out-of-bounds");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            0,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_liquidityTooHigh() public {
        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/liquidity-out-of-bounds");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            type(uint128).max,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_rateLimitExceeded_token0() public {
        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey, 1, 0);
        vm.stopPrank();

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_rateLimitExceeded_token1() public {
        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey, 1, 0);
        vm.stopPrank();

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_minAmount0BelowBound() public {
        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            UniswapV3Lib.TokenAmounts({ amount0: 0, amount1: defaultMinAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    function test_removeLiquidityUniswapV3_minAmount1BelowBound() public {
        vm.startPrank(relayer);
        vm.expectRevert("UniswapV3Lib/min-amount-below-bound");
        mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId,
            liquidity,
            UniswapV3Lib.TokenAmounts({ amount0: defaultMinAmount0, amount1: 0 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
}

contract MainnetControllerRemoveLiquidityE2EUniswapV3Test is UniswapV3TestBase {
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
            UniswapV3Lib.Tick({lower : -100, upper : 100})
        );
    }

    function _addLiquidity(uint256 addAmount0, uint256 addAmount1, UniswapV3Lib.Tick memory addTickDelta) internal returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0Used, uint256 amount1Used) {
        deal(address(token0), address(almProxy), addAmount0);
        deal(address(token1), address(almProxy), addAmount1);

        (tokenId_, liquidity_, amount0Used, amount1Used) = _addLiquidity(
            0,
            UniswapV3Lib.Tick({lower : _toSpacedTick(initTick + addTickDelta.lower), upper : _toSpacedTick(initTick + addTickDelta.upper)}),
            UniswapV3Lib.TokenAmounts({ amount0: addAmount0, amount1: addAmount1 }),
            _minLiquidityPosition(addAmount0, addAmount1)
        );

        vm.warp(block.timestamp + 2 hours); // Advance sufficient time for twap
    }

    function _removeLiquidityAndValidate(uint256 tokenId_, uint128 liquidity_, uint256 minAmount0, uint256 minAmount1, bytes32 token0RateLimitKey, bytes32 token1RateLimitKey) internal returns (uint256 amount0Used, uint256 amount1Used) {
        uint256 token0RateLimitBefore = rateLimits.getCurrentRateLimit(token0RateLimitKey);
        uint256 token1RateLimitBefore = rateLimits.getCurrentRateLimit(token1RateLimitKey);

        vm.startPrank(relayer);
        (amount0Used, amount1Used) = mainnetController.removeLiquidityUniswapV3(
            _getPool(),
            tokenId_,
            liquidity_,
            UniswapV3Lib.TokenAmounts({ amount0: minAmount0, amount1: minAmount1 }),
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGe(amount0Used, minAmount0, "amount0Used should be greater than or equal to minAmount0");
        assertGe(amount1Used, minAmount1, "amount1Used should be greater than or equal to minAmount1");

        assertApproxEqRel(amount0Used, amount0Added * liquidity_ / totalLiquidity, .0001e18, "amount0Used should be within 0.01% of amount0Added * liquidity / totalLiquidity");
        assertApproxEqRel(amount1Used, amount1Added * liquidity_ / totalLiquidity, .0001e18, "amount1Used should be within 0.01% of amount1Added * liquidity / totalLiquidity");

        uint256 token0RateLimitAfter = rateLimits.getCurrentRateLimit(token0RateLimitKey);
        uint256 token1RateLimitAfter = rateLimits.getCurrentRateLimit(token1RateLimitKey);

        assertEq(token0RateLimitBefore - token0RateLimitAfter, amount0Used, "token0 rate limit delta mismatch");
        assertEq(token1RateLimitBefore - token1RateLimitAfter, amount1Used, "token1 rate limit delta mismatch");
    }
}

contract MainnetControllerRemoveLiquidityE2EUniswapV3UsdcUsdtTest is MainnetControllerRemoveLiquidityE2EUniswapV3Test {
    function test_e2e_addRemoveLiquidityUniswapV3_usdcUsdt(uint128 liquidity) public {
        liquidity = uint128(bound(uint256(liquidity), 1000000, uint256(totalLiquidity)));

        uint256 minAmount0 = amount0Added * liquidity / totalLiquidity;
        uint256 minAmount1 = amount1Added * liquidity / totalLiquidity;

        _removeLiquidityAndValidate(
            tokenId,
            liquidity,
            minAmount0 * 9999/10000,
            minAmount1 * 9999/10000,
            uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey,
            uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey
        );
    }

    function test_e2e_removeLiquidityUniswapV3_usdcUsdt_allLiquidity() public {
        _removeLiquidityAndValidate(
            tokenId,
            totalLiquidity,
            amount0Added * 9999/10000,
            amount1Added * 9999/10000,
            uniswapV3_UsdcUsdtPool_UsdcRemoveLiquidityKey,
            uniswapV3_UsdcUsdtPool_UsdtRemoveLiquidityKey
        );
    }
}

contract MainnetControllerRemoveLiquidityE2EUniswapV3DaiUsdcTest is MainnetControllerRemoveLiquidityE2EUniswapV3Test {
    function _defaultAddLiquidity() internal override virtual {
        uint256 addAmount = 1_000_000e18;

        uint256 addAmount0 = addAmount * 10**token0.decimals() / 10**18;
        uint256 addAmount1 = addAmount * 10**token1.decimals() / 10**18;

        // Pool is slightly overweight DAI
        addAmount1 = addAmount1 * 93 / 100;

        (tokenId, totalLiquidity, amount0Added, amount1Added) = _addLiquidity(
            addAmount0,
            addAmount1,
            UniswapV3Lib.Tick({lower : -100, upper : 100})
        );
    }

    function _getPool() internal pure override returns (address) {
        return UNISWAP_V3_DAI_USDC_POOL;
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
            uniswapV3_DaiUsdcPool_DaiRemoveLiquidityKey,
            uniswapV3_DaiUsdcPool_UsdcRemoveLiquidityKey
        );
    }

    function test_e2e_removeLiquidityUniswapV3_daiUsdc_allLiquidity() public {
        _removeLiquidityAndValidate(
            tokenId,
            totalLiquidity,
            amount0Added * 9999/10000,
            amount1Added * 9999/10000,
            uniswapV3_DaiUsdcPool_DaiRemoveLiquidityKey,
            uniswapV3_DaiUsdcPool_UsdcRemoveLiquidityKey
        );
    }
}

// Adapted from Certora's findings: https://gist.github.com/3docSec/616413000a6ebb154211db74589e0782
contract MainnetControllerSwapSandwichAttackTest is UniswapV3TestBase {
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
        bytes32 swapKey = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_UNISWAP_V3_SWAP(),
            address(usdc),
            pool
        );

        vm.startPrank(GROVE_PROXY);
        rateLimits.setUnlimitedRateLimitData(swapKey);
        // Allow up to ~1% local slippage
        mainnetController.setMaxSlippage(pool, 0.99e18);
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

        vm.startPrank(relayer);
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

        assertLe(attackerFinalUsdc,                attackerInitialUsdc,               "attacker should have lower or same balance of USDC as before attack");
        assertEq(victimAmountIn,                   usdc.balanceOf(address(almProxy)), "proxy should have same balance of USDC as before attack");
        assertEq(dai.balanceOf(address(almProxy)), victimDaiBalanceBefore,            "proxy should have same balance of DAI as before attack");
    }
}
