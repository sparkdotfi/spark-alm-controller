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

import { UniV4Params } from "../../src/libraries/UniswapV4Lib.sol";

import { LiquidityAmounts } from "../../src/libraries/UniLiquidityAmounts.sol";

import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC721 }        from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import "./ForkTestBase.t.sol";

contract UniV4TestBase is ForkTestBase {

    struct MintPositionResult {
        uint256 tokenId;
        uint256 amount0Spent;
        uint256 amount1Spent;
        uint128 liquidity;
        int24   tickLower;
        int24   tickUpper;
    }

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
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(ADDR_ID, 0.98e18);
        mainnetController.setUniV4tickLimits(POOL_ID, -60, 60);
        vm.stopPrank();
    }

    function _mintPosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityInitial
    ) internal returns (MintPositionResult memory result) {
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            tickLower,
            tickUpper,
            liquidityInitial
        );

        uint256 tokenIdToMint = posm.nextTokenId();

        uint256 usdcStarting = usdc.balanceOf(address(almProxy));
        uint256 usdtStarting = usdt.balanceOf(address(almProxy));

        deal(address(usdc), address(almProxy), usdcStarting + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdtStarting + amount1Forecasted + 1);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        vm.prank(relayer);
        mainnetController.mintPositionUniV4({
            poolId           : POOL_ID,
            tickLower        : tickLower,
            tickUpper        : tickUpper,
            liquidityInitial : liquidityInitial,
            amount0Max       : amount0Forecasted + 1,
            amount1Max       : amount1Forecasted + 1
        });

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        result.tokenId     = tokenIdToMint;
        result.amount0Spent = usdcBeforeCall - usdcAfterCall;
        result.amount1Spent = usdtBeforeCall - usdtAfterCall;
        result.liquidity    = liquidityInitial;
        result.tickLower    = tickLower;
        result.tickUpper    = tickUpper;
    }

    function _quoteLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityAmount
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(PoolId.wrap(POOL_ID));
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );
    }

    function _assertZeroAllowances() internal {
        (uint160 usdcAllowance,,) = permit2.allowance(address(almProxy), address(usdc), address(posm));
        (uint160 usdtAllowance,,) = permit2.allowance(address(almProxy), address(usdt), address(posm));
        assertEq(usdcAllowance, 0, "permit2 usdc allowance");
        assertEq(usdtAllowance, 0, "permit2 usdt allowance");
        assertEq(usdc.allowance(address(almProxy), address(permit2)), 0, "token usdc allowance");
        assertEq(usdt.allowance(address(almProxy), address(permit2)), 0, "token usdt allowance");
    }

    function _to18Decimals(uint256 amountSixDecimals) internal pure returns (uint256) {
        return amountSixDecimals * 1e12;
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

    function test_mintPositionUniV4_revertsForNonRelayer() public {
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(-10, 0, 1_000_000e6);

        uint256 usdcStarting = usdc.balanceOf(address(almProxy));
        uint256 usdtStarting = usdt.balanceOf(address(almProxy));
        deal(address(usdc), address(almProxy), usdcStarting + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdtStarting + amount1Forecasted + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                mainnetController.RELAYER()
            )
        );
        mainnetController.mintPositionUniV4({
            poolId           : POOL_ID,
            tickLower        : -10,
            tickUpper        : 0,
            liquidityInitial : 1_000_000e6,
            amount0Max       : amount0Forecasted + 1,
            amount1Max       : amount1Forecasted + 1
        });
    }

    function test_mintPositionUniV4_revertsWhenTickOutsideConfiguredBounds() public {
        vm.startPrank(relayer);
        vm.expectRevert("tickLower too low");
        mainnetController.mintPositionUniV4({
            poolId           : POOL_ID,
            tickLower        : -120,
            tickUpper        : -10,
            liquidityInitial : 1_000_000e6,
            amount0Max       : 1,
            amount1Max       : 1
        });
        vm.stopPrank();
    }

    function test_mintPositionUniV4_revertsWhenAmount0MaxTooHigh() public {
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(-10, 0, 1_000_000e6);

        uint256 excessiveAmount0Max = amount0Forecasted + 1_000_000;

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV4Lib: amount0Max too high");
        mainnetController.mintPositionUniV4({
            poolId           : POOL_ID,
            tickLower        : -10,
            tickUpper        : 0,
            liquidityInitial : 1_000_000e6,
            amount0Max       : excessiveAmount0Max,
            amount1Max       : amount1Forecasted + 1
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniV4_revertsWhenPoolIdDoesNotMatchToken() public {
        MintPositionResult memory result = _mintPosition(-10, 0, 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV4Lib: tokenId poolId mismatch");
        mainnetController.increaseLiquidityUniV4({
            poolId            : bytes32(uint256(keccak256("WRONG"))),
            tokenId           : result.tokenId,
            liquidityIncrease : 10_000e6,
            amount0Max        : 1,
            amount1Max        : 1
        });
        vm.stopPrank();
    }

    function test_burnPositionUniV4_revertsWhenPoolIdDoesNotMatchToken() public {
        MintPositionResult memory result = _mintPosition(-10, 0, 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("UniswapV4Lib: tokenId poolId mismatch");
        mainnetController.burnPositionUniV4({
            poolId     : bytes32(uint256(keccak256("WRONG"))),
            tokenId    : result.tokenId,
            amount0Min : 0,
            amount1Min : 0
        });
        vm.stopPrank();
    }

}

contract MainnetControllerMintPositionUniV4SuccessTests is UniV4TestBase {

    function test_mintPositionUniV4_mintsPositionAndResetsApprovals() public {
        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(DEPOSIT_LIMIT_KEY);

        MintPositionResult memory minted = _mintPosition(-10, 0, 1_000_000e6);

        assertEq(IERC721(address(posm)).ownerOf(minted.tokenId), address(almProxy));
        assertEq(posm.getPositionLiquidity(minted.tokenId), minted.liquidity);

        _assertZeroAllowances();

        uint256 depositLimitAfter = rateLimits.getCurrentRateLimit(DEPOSIT_LIMIT_KEY);
        assertLe(depositLimitAfter, initialDepositLimit);
        uint256 expectedDecrease = _to18Decimals(minted.amount0Spent) + _to18Decimals(minted.amount1Spent);
        assertEq(initialDepositLimit - depositLimitAfter, expectedDecrease);
    }

    function test_increaseLiquidityUniV4_increasesLiquidityAndUpdatesRateLimit() public {
        MintPositionResult memory minted = _mintPosition(-10, 0, 1_000_000e6);

        uint128 liquidityIncrease = 250_000e6;
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            liquidityIncrease
        );

        uint256 depositLimitBefore = rateLimits.getCurrentRateLimit(DEPOSIT_LIMIT_KEY);

        uint256 usdcStarting = usdc.balanceOf(address(almProxy));
        uint256 usdtStarting = usdt.balanceOf(address(almProxy));
        deal(address(usdc), address(almProxy), usdcStarting + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdtStarting + amount1Forecasted + 1);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint128 liquidityBefore = posm.getPositionLiquidity(minted.tokenId);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniV4({
            poolId            : POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Forecasted + 1,
            amount1Max        : amount1Forecasted + 1
        });

        uint128 liquidityAfter = posm.getPositionLiquidity(minted.tokenId);
        assertEq(liquidityAfter, liquidityBefore + liquidityIncrease);

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        uint256 amount0Spent = usdcBeforeCall - usdcAfterCall;
        uint256 amount1Spent = usdtBeforeCall - usdtAfterCall;

        _assertZeroAllowances();

        uint256 depositLimitAfter = rateLimits.getCurrentRateLimit(DEPOSIT_LIMIT_KEY);
        assertLe(depositLimitAfter, depositLimitBefore);
        uint256 expectedDecrease = _to18Decimals(amount0Spent) + _to18Decimals(amount1Spent);
        assertEq(depositLimitBefore - depositLimitAfter, expectedDecrease);
    }

    function test_decreaseLiquidityUniV4_returnsPartialLiquidity() public {
        MintPositionResult memory minted = _mintPosition(-10, 0, 1_000_000e6);

        uint128 liquidityDecrease = minted.liquidity / 2;
        (uint256 amount0Expected, uint256 amount1Expected) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            liquidityDecrease
        );

        uint256 withdrawLimitBefore = rateLimits.getCurrentRateLimit(WITHDRAW_LIMIT_KEY);

        uint256 usdcBefore = usdc.balanceOf(address(almProxy));
        uint256 usdtBefore = usdt.balanceOf(address(almProxy));

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniV4({
            poolId            : POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Expected > 0 ? amount0Expected - 1 : 0,
            amount1Min        : amount1Expected > 0 ? amount1Expected - 1 : 0
        });

        uint256 usdcAfter = usdc.balanceOf(address(almProxy));
        uint256 usdtAfter = usdt.balanceOf(address(almProxy));

        uint256 usdcDelta = usdcAfter - usdcBefore;
        uint256 usdtDelta = usdtAfter - usdtBefore;

        assertGe(usdcDelta, amount0Expected > 0 ? amount0Expected - 1 : 0);
        assertGe(usdtDelta, amount1Expected > 0 ? amount1Expected - 1 : 0);

        uint128 liquidityAfter = posm.getPositionLiquidity(minted.tokenId);
        assertEq(liquidityAfter, minted.liquidity - liquidityDecrease);

        uint256 withdrawLimitAfter = rateLimits.getCurrentRateLimit(WITHDRAW_LIMIT_KEY);
        assertLe(withdrawLimitAfter, withdrawLimitBefore);
        uint256 expectedDecrease = _to18Decimals(usdcDelta) + _to18Decimals(usdtDelta);
        assertEq(withdrawLimitBefore - withdrawLimitAfter, expectedDecrease);

        _assertZeroAllowances();
    }

    function test_burnPositionUniV4_closesPositionAndReclaimsAssets() public {
        MintPositionResult memory minted = _mintPosition(-10, 0, 1_000_000e6);

        uint256 withdrawLimitBefore = rateLimits.getCurrentRateLimit(WITHDRAW_LIMIT_KEY);

        uint256 usdcBefore = usdc.balanceOf(address(almProxy));
        uint256 usdtBefore = usdt.balanceOf(address(almProxy));

        uint256 amount0Min = minted.amount0Spent > 0 ? minted.amount0Spent - 1 : 0;
        uint256 amount1Min = minted.amount1Spent > 0 ? minted.amount1Spent - 1 : 0;

        vm.prank(relayer);
        mainnetController.burnPositionUniV4({
            poolId     : POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : amount0Min,
            amount1Min : amount1Min
        });

        uint256 usdcAfter = usdc.balanceOf(address(almProxy));
        uint256 usdtAfter = usdt.balanceOf(address(almProxy));

        uint256 usdcDelta = usdcAfter - usdcBefore;
        uint256 usdtDelta = usdtAfter - usdtBefore;

        assertGe(usdcDelta, amount0Min);
        assertGe(usdtDelta, amount1Min);

        vm.expectRevert();
        IERC721(address(posm)).ownerOf(minted.tokenId);

        uint256 withdrawLimitAfter = rateLimits.getCurrentRateLimit(WITHDRAW_LIMIT_KEY);
        assertLe(withdrawLimitAfter, withdrawLimitBefore);
        uint256 expectedDecrease = _to18Decimals(usdcDelta) + _to18Decimals(usdtDelta);
        assertEq(withdrawLimitBefore - withdrawLimitAfter, expectedDecrease);

        _assertZeroAllowances();
    }

}
