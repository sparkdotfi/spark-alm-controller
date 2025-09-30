// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { Currency }     from "v4-core/types/Currency.sol";
import { IHooks }       from "v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolId }       from "v4-core/types/PoolId.sol";
import { PoolKey }      from "v4-core/types/PoolKey.sol";
import { TickMath }     from "v4-core/libraries/TickMath.sol";

import { Actions }          from "v4-periphery/src/libraries/Actions.sol";
import { PositionInfo }     from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { IStateView }       from "v4-periphery/src/interfaces/IStateView.sol";

import "forge-std/console2.sol";

import { LiquidityAmounts } from "../../src/vendor/LiquidityAmounts.sol";

import { UniV4Params } from "../../src/libraries/UniswapV4Lib.sol";

import "./ForkTestBase.t.sol";

contract UniV4TestBase is ForkTestBase {

    bytes32 public LIMIT_DEPOSIT  = keccak256("LIMIT_UNI_V4_DEPOSIT");
    bytes32 public LIMIT_WITHDRAW = keccak256("LIMIT_UNI_V4_WITHDRAW");

    // IPoolManager     public constant poolm      = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager public constant posm       = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    IStateView       public constant stateView  = IStateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IPermit2         public constant permit2    = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Uniswap V4 USDC/USDT pool
    bytes32 constant POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;
    address constant ADDR_ID = address(uint160(uint256(POOL_ID)));

    bytes32 DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(LIMIT_DEPOSIT, POOL_ID));
    bytes32 WITHDRAW_LIMIT_KEY = keccak256(abi.encode(LIMIT_WITHDRAW, POOL_ID));

    function setUp() public virtual override  {
        super.setUp();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(WITHDRAW_LIMIT_KEY, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(ADDR_ID, 0.98e18);
    }

    function _mintPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityInitial
    ) internal {
        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(PoolId.wrap(POOL_ID));
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityInitial
        );

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);
        mainnetController.mintPositionUniV4({
            poolId           : POOL_ID,
            tickLower        : tickLower,
            tickUpper        : tickUpper,
            liquidityInitial : liquidityInitial,
            amount0Max       : amount0Forecasted + 1,
            amount1Max       : amount1Forecasted + 1
        });
    }

    function _addLiquidity(uint256 usdcAmount, uint256 usdtAmount) internal {
        // deal(address(usdc), address(almProxy), usdcAmount);
        // deal(address(usdt), address(almProxy), usdtAmount);
        //
        // uint256[] memory amounts = new uint256[](2);
        // amounts[0] = usdcAmount;
        // amounts[1] = usdtAmount;
        //
        // uint256 minLpAmount = (usdcAmount + usdtAmount) * 1e12 * 98/100;

        // vm.prank(relayer);
        // return mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function _addLiquidity() internal {
        return _addLiquidity(1_000_000e6, 1_000_000e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23470490; // September 29, 2025
    }

}

contract MainnetControllerMintPositionUniV4FailureTests is UniV4TestBase {

    // function test_mintPositionUniV4_notRelayer() public {
    // function test_mintPositionUniV4

}

contract MainnetControllerMintPositionUniV4SuccessTests is UniV4TestBase {

    function test_mintLiquidityUniV4() public {
        assertEq(rateLimits.getCurrentRateLimit(DEPOSIT_LIMIT_KEY), 2_000_000e18);

        _mintPosition(
            -10,
            0,
            1_000_000e6
        );

        // assertEq(usdc.allowance(address(almProxy), address(posm)), 0);
        //%

    }

}
