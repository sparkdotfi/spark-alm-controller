// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Currency }     from "v4-core/types/Currency.sol";
import { IHooks }       from "v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolId }       from "v4-core/types/PoolId.sol";
import { PoolKey }      from "v4-core/types/PoolKey.sol";
import { TickMath }     from "v4-core/libraries/TickMath.sol";

import { Actions }          from "v4-periphery/src/libraries/Actions.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { IStateView }      from "v4-periphery/src/interfaces/IStateView.sol";

import { LiquidityAmounts } from "../../src/vendor/LiquidityAmounts.sol";

import { ICurvePoolLike } from "../../src/libraries/CurveLib.sol";
import "./ForkTestBase.t.sol";

contract UniV4TestBase is ForkTestBase {

    bytes32 public LIMIT_UNI_V4_DEPOSIT       = keccak256("LIMIT_UNI_V4_DEPOSIT");

    IPoolManager      public poolm = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager  public posm  = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    // Uniswap V4 USDC/USDT pool
    bytes32 constant POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    bytes32 depositRateLimitKey = keccak256(abi.encode(LIMIT_UNI_V4_DEPOSIT, POOL_ID));
    // bytes32 withdrawRateLimitKey = keccak256(abi.encode(LIMIT_UNI_V4_WITHDRAW, id));

    function setUp() public virtual override  {
        super.setUp();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(depositRateLimitKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        // rateLimits.setRateLimitData(withdrawRateLimitKey, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        // vm.prank(SPARK_PROXY);
        // mainnetController.setMaxSlippage(CURVE_POOL, 0.98e18);
    }

    function _addLiquidity(uint256 usdcAmount, uint256 usdtAmount)
        internal returns (uint256 lpTokensReceived)
    {
        deal(address(usdc), address(almProxy), usdcAmount);
        deal(address(usdt), address(almProxy), usdtAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = usdtAmount;

        uint256 minLpAmount = (usdcAmount + usdtAmount) * 1e12 * 98/100;

        // vm.prank(relayer);
        // return mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function _addLiquidity() internal returns (uint256 lpTokensReceived) {
        return _addLiquidity(1_000_000e6, 1_000_000e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

}

contract MainnetControllerAddLiquidityUniV4FailureTests is UniV4TestBase {

}

contract MainnetControllerAddLiquidityUniV4SuccessTests is UniV4TestBase {

    function test_addLiquidityUniV4() public {
        PoolKey memory key = PoolKey({
            currency0      : Currency.wrap(address(usdc)),
            currency1      : Currency.wrap(address(usdt)),
            fee         : 10,
            tickSpacing : 1,
            hooks       : IHooks(address(0))
        });
        PoolId id = key.toId();
        address addr_id = address(uint160(uint256(PoolId.unwrap(id))));
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(addr_id, 0.98e18);

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 startingUsdtBalance = usdt.balanceOf(address(poolm));
        uint256 startingUsdcBalance = usdc.balanceOf(address(poolm));
        // uint256 startingTotalSupply = curveLp.totalSupply();

        assertEq(usdc.allowance(address(almProxy), address(posm)), 0);
        assertEq(usdt.allowance(address(almProxy), address(posm)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(poolm)),        startingUsdcBalance);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(address(poolm)),        startingUsdtBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositRateLimitKey), 2_000_000e18);
        (uint160 sqrtPriceX96,,,) = mainnetController.uniV4stateView().getSlot0(id);
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-10),
            TickMath.getSqrtPriceAtTick(0),
            1e6
        );
        vm.prank(relayer);
        mainnetController.addLiquidityUniV4({
            poolId      : PoolId.unwrap(id),
            // token0      : address(usdc),
            // token1      : address(usdt),
            // fee         : 10,
            // tickSpacing : 1,
            // hooks       : address(0),
            tickLower   : -10,
            tickUpper   : 0,
            liquidity   : 1e6,
            amount0Max  : amount0Forecasted + 1,
            amount1Max  : amount1Forecasted + 1
        });

        // assertEq(lpTokensReceived, 1_987_199.361495730708108741e18);
        //
        // assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        // assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);
        //
        // assertEq(usdc.balanceOf(address(almProxy)), 0);
        // assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance + 1_000_000e6);
        //
        // assertEq(usdt.balanceOf(address(almProxy)), 0);
        // assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance + 1_000_000e6);
        //
        // assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        // assertEq(curveLp.totalSupply(),                startingTotalSupply + lpTokensReceived);
        //
        // // NOTE: A large swap happened because of the balances in the pool being skewed towards USDT.
        // assertEq(rateLimits.getCurrentRateLimit(depositRateLimitKey), 0);
        // assertEq(rateLimits.getCurrentRateLimit(curveSwapKey),    465_022.869727319215817005e18);
    }

    // function test_addLiquidityCurve_swapRateLimit() public {
    //     // Set a higher slippage to allow for successes
    //     vm.prank(SPARK_PROXY);
    //     mainnetController.setMaxSlippage(CURVE_POOL, 0.7e18);
    //
    //     deal(address(usdc), address(almProxy), 1_000_000e6);
    //
    //     // Step 1: Add liquidity, check how much the rate limit was reduced
    //
    //     uint256[] memory amounts = new uint256[](2);
    //     amounts[0] = 1_000_000e6;
    //     amounts[1] = 0;
    //
    //     uint256 minLpAmount = 800_000e18;
    //
    //     uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);
    //
    //     vm.startPrank(relayer);
    //
    //     uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    //
    //     uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);
    //
    //     // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool
    //
    //     // NOTE: These values are skewed because pool balance is skewed.
    //     uint256[] memory minWithdrawnAmounts = new uint256[](2);
    //     minWithdrawnAmounts[0] = 260_000e6;
    //     minWithdrawnAmounts[1] = 730_000e6;
    //
    //     uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);
    //
    //     // Step 3: Calculate the average difference between the assets deposited and withdrawn, into an average swap amount
    //     //         and compare against the derived swap amount
    //
    //     uint256[] memory rates = ICurvePoolLike(CURVE_POOL).stored_rates();
    //
    //     uint256 totalSwapped;
    //     for (uint256 i; i < withdrawnAmounts.length; i++) {
    //         totalSwapped += _absSubtraction(withdrawnAmounts[i] * rates[i], amounts[i] * rates[i]) / 1e18;
    //     }
    //     totalSwapped /= 2;
    //
    //     // Difference is accurate to within 1 unit of USDC
    //     assertApproxEqAbs(derivedSwapAmount, totalSwapped, 0.000001e18);
    //
    //     // Check real values, comparing amount of USDC deposited with amount withdrawn as a result of the "swap"
    //     assertEq(withdrawnAmounts[0], 265_480.996766e6);
    //     assertEq(withdrawnAmounts[1], 734_605.036920e6);
    //
    //     // Some accuracy differences because of fees
    //     assertEq(derivedSwapAmount,                 734_562.020077130663332756e18);
    //     assertEq(1_000_000e6 - withdrawnAmounts[0], 734_519.003234e6);
    // }

}
