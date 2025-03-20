// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

import { ICurvePoolLike } from "../../src/MainnetController.sol";

interface ICurvePool is IERC20, ICurvePoolLike {
    function balances(uint256 index) external view returns (uint256);
}

contract ControllerHandler is Test {

    address immutable almProxy;
    address immutable relayer;

    IERC20 immutable asset1;
    IERC20 immutable asset2;

    ICurvePool        immutable pool;
    MainnetController immutable controller;

    uint256 immutable asset1Precision;
    uint256 immutable asset2Precision;

    uint256 public totalValueDeposited;
    uint256 public totalValueWithdrawn;

    constructor(
        address almProxy_,
        address controller_,
        address pool_,
        address relayer_,
        address asset1_,
        address asset2_
    ) {
        almProxy = almProxy_;
        relayer  = relayer_;

        asset1 = IERC20(asset1_);
        asset2 = IERC20(asset2_);

        asset1Precision = 10 ** asset1.decimals();
        asset2Precision = 10 ** asset2.decimals();

        pool       = ICurvePool(pool_);
        controller = MainnetController(controller_);
    }

    function addLiquidity(uint256 asset1Amount, uint256 asset2Amount) public {
        // Using a higher lower bound to have reasonable and practical precision calculations
        asset1Amount = _bound(asset1Amount, 1 * asset1Precision, 100_000_000 * asset1Precision);
        asset2Amount = _bound(asset2Amount, 1 * asset2Precision, 100_000_000 * asset2Precision);

        deal(address(asset1), almProxy, asset1Amount);
        deal(address(asset2), almProxy, asset2Amount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = asset1Amount;
        amounts[1] = asset2Amount;

        uint256[] memory rates = pool.stored_rates();

        uint256 totalDeposit = (asset1Amount * rates[0] + asset2Amount * rates[1]) / 1e18;

        totalValueDeposited += totalDeposit;

        uint256 minLpAmount = totalDeposit
            * (controller.maxSlippages(address(pool)) + 0.0001e18)
            / pool.get_virtual_price();

        vm.startPrank(relayer);
        try controller.addLiquidityCurve(address(pool), amounts, minLpAmount) {}
        catch {
            // If the transaction fails because of slippage, update params to be closer to whats in the pool
            uint256 convertedAsset1Amount = asset1Amount * asset2Precision / asset1Precision;
            asset2Amount = _bound(convertedAsset1Amount, asset1Amount * 99/100, asset1Amount * 101/100);
            controller.addLiquidityCurve(address(pool), amounts, minLpAmount);
        }
        vm.stopPrank();

        uint256 lpValue = pool.balanceOf(address(almProxy)) * pool.get_virtual_price() / 1e18;

        // console.log("\n--- Deposit");
        // console.log("asset1Amount", asset1Amount * 1e12);
        // console.log("asset2Amount", asset2Amount);
        // console.log("lpValue     ", lpValue);
        // console.log("totalDeposit", totalDeposit);
    }

    function removeLiquidity(uint256 lpAmount) public {
        // Using a higher lower bound to have reasonable and practical precision calculations
        if (pool.balanceOf(almProxy) < 0.5e18) return;

        lpAmount = _bound(lpAmount, 0.5e18, pool.balanceOf(almProxy));

        uint256 lpValue = lpAmount * pool.get_virtual_price() / 1e18;


        uint256 claimableAsset1 = pool.balances(0) * lpAmount / pool.totalSupply();
        uint256 claimableAsset2 = pool.balances(1) * lpAmount / pool.totalSupply();

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = claimableAsset1;
        minAmounts[1] = claimableAsset2;

        vm.prank(relayer);
        uint256[] memory amounts = controller.removeLiquidityCurve(address(pool), lpAmount, minAmounts);

        uint256[] memory rates = pool.stored_rates();

        uint256 totalWithdraw = (amounts[0] * rates[0] + amounts[1] * rates[1]) / 1e18;

        totalValueWithdrawn += totalWithdraw;

        // console.log("\n--- Withdraw");
        // console.log("claimableAsset1", claimableAsset1 * 1e12);
        // console.log("claimableAsset2", claimableAsset2);
        // console.log("lpBurned       ", lpValue);
        // console.log("totalWithdraw  ", totalWithdraw);
    }

    function swap(uint256 swapAmount, bool direction) public {
        // direction: true = asset1 -> asset2, false = asset2 -> asset1
        uint256 assetInPrecision  = direction ? asset1Precision : asset2Precision;
        uint256 assetOutPrecision = direction ? asset2Precision : asset1Precision;
        uint256 swapInIndex       = direction ? 0 : 1;
        uint256 swapOutIndex      = direction ? 1 : 0;

        address asset = direction ? address(asset1) : address(asset2);

        // Remove up to 10% of other assets balance to avoid slippage causing reverts
        uint256 maxSwapAmount = pool.balances(swapOutIndex) * assetInPrecision / assetOutPrecision / 10;

        swapAmount = _bound(swapAmount, 1 * assetInPrecision, maxSwapAmount);

        deal(asset, almProxy, swapAmount);

        uint256 minAmountOut = swapAmount
            * (controller.maxSlippages(address(pool)) + 0.0001e18)
            * assetOutPrecision
            / assetInPrecision
            / 1e18;

        console.log("\n--- Swap");
        console.log("balances(swapInIndex) ", pool.balances(swapInIndex) * 1e18 / assetInPrecision);
        console.log("balances(swapOutIndex)", pool.balances(swapOutIndex) * 1e18 / assetOutPrecision);
        console.log("swapAmount            ", swapAmount * 1e18 / assetInPrecision);
        console.log("minAmountOut          ", minAmountOut * 1e18 / assetOutPrecision);
        // console.log("lpBurned       ", lpValue);
        // console.log("totalWithdraw  ", totalWithdraw);

        vm.startPrank(relayer);
        try controller.swapCurve(
            address(pool),
            swapInIndex,
            swapOutIndex,
            swapAmount,
            minAmountOut
        ) {}
        catch {
            // If the swap slippage is too high, swap the other way
            swapAmount   = swapAmount * assetOutPrecision / assetInPrecision;
            minAmountOut = minAmountOut * assetOutPrecision / assetInPrecision;
            controller.swapCurve(
                address(pool),
                swapOutIndex,
                swapInIndex,
                swapAmount,
                minAmountOut
            );
        }
        vm.stopPrank();




    }

}

contract CurveFuzzTestsBase is ForkTestBase {

    address constant RLUSD      = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address constant CURVE_POOL = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    IERC20 rlUsd = IERC20(RLUSD);

    ICurvePool curvePool = ICurvePool(CURVE_POOL);

    ControllerHandler handler;

    function setUp() public virtual override  {
        super.setUp();

        bytes32 curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        bytes32 curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        bytes32 curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(curveDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.99e18);

        handler = new ControllerHandler(
            address(almProxy),
            address(mainnetController),
            CURVE_POOL,
            relayer,
            address(usdc),
            RLUSD
        );

        targetContract(address(handler));
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function statefulFuzz_curve_test() public {
        uint256 lpValue = curvePool.balanceOf(address(almProxy)) * curvePool.get_virtual_price() / 1e18;

        // console.log("\n--- Test");

        // console.log("lpValue ", lpValue);
        // console.log("deposit ", handler.totalValueDeposited());
        // console.log("withdraw", handler.totalValueWithdrawn());
        // console.log("d - w   ", handler.totalValueDeposited() - handler.totalValueWithdrawn());
        // console.log("d - w 2 ", (handler.totalValueDeposited() - handler.totalValueWithdrawn()) * 99/100);

        assertGe(handler.totalValueWithdrawn() + lpValue, handler.totalValueDeposited() * 99/100);
    }

}


