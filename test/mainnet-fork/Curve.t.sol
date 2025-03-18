// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

import { ICurvePoolLike } from "../../src/MainnetController.sol";

contract CurveTestBase is ForkTestBase {

    address constant RLUSD      = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address constant CURVE_POOL = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    IERC20 rlUsd   = IERC20(RLUSD);
    IERC20 curveLp = IERC20(CURVE_POOL);

    ICurvePoolLike curvePool = ICurvePoolLike(CURVE_POOL);

    bytes32 curveDepositKey;
    bytes32 curveSwapKey;
    bytes32 curveWithdrawKey;

    function setUp() public virtual override  {
        super.setUp();

        curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.98e18);
    }

    function _addLiquidity(uint256 usdcAmount, uint256 rlUsdAmount)
        internal returns (uint256 lpTokensReceived)
    {
        deal(address(usdc), address(almProxy), usdcAmount);
        deal(RLUSD,         address(almProxy), rlUsdAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = rlUsdAmount;

        uint256 minLpAmount = (usdcAmount * 1e12 + rlUsdAmount) * 98/100;

        vm.prank(relayer);
        return mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function _addLiquidity() internal returns (uint256 lpTokensReceived) {
        return _addLiquidity(1_000_000e6, 1_000_000e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

}

contract MainnetControllerAddLiquidityCurveFailureTests is CurveTestBase {

    function test_addLiquidityCurve_notRelayer() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_slippageNotSet() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_invalidDepositAmountsLength() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;
        amounts[2] = 1_000_000e18;

        uint256 minLpAmount = 0;

        vm.startPrank(relayer);

        vm.expectRevert("MainnetController/invalid-deposit-amounts");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256[] memory amounts2 = new uint256[](1);
        amounts[0] = 1_000_000e6;

        vm.expectRevert("MainnetController/invalid-deposit-amounts");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts2, minLpAmount);
    }

    function test_addLiquidityCurve_underAllowableSlippageBoundary() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(RLUSD,         address(almProxy), 1_000_000e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 boundaryAmount = 2_000_000e18 * 0.98e18 / curvePool.get_virtual_price();

        assertApproxEqAbs(boundaryAmount, 1_950_000e18, 50_000e18);  // Sanity check on precision

        uint256 minLpAmount = boundaryAmount - 1;

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        minLpAmount = boundaryAmount;

        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_zeroMaxAmount() public {
        bytes32 curveDeposit = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDeposit, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset0() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(RLUSD,         address(almProxy), 1_000_000e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6 + 1;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[0] = 1_000_000e6;

        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset1() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(RLUSD,         address(almProxy), 1_000_000e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18 + 1;

        uint256 minLpAmount = 1_990_000e18;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[1] = 1_000_000e18;

        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

}

contract MainnetControllerAddLiquiditySuccessTests is CurveTestBase {

    function test_addLiquidityCurve() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(RLUSD,         address(almProxy), 1_000_000e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        uint256 startingPyUsdBalance = rlUsd.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply  = curveLp.totalSupply();

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(rlUsd.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(rlUsd.balanceOf(CURVE_POOL),        startingPyUsdBalance);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveDepositKey), 2_000_000e18);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(
            CURVE_POOL,
            amounts,
            minLpAmount
        );

        assertEq(lpTokensReceived, 1_997_612.166757892422937582e18);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance + 1_000_000e6);

        assertEq(rlUsd.balanceOf(address(almProxy)), 0);
        assertEq(rlUsd.balanceOf(CURVE_POOL),        startingPyUsdBalance + 1_000_000e18);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply + lpTokensReceived);

        assertEq(rateLimits.getCurrentRateLimit(curveDepositKey), 0);
    }

}

contract MainnetControllerRemoveLiquidityCurveFailureTests is CurveTestBase {

    function test_removeLiquidityCurve_notRelayer() public {
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e18;

        uint256 lpReturn = 1_980_000e18;

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_slippageNotSet() public {
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e18;

        uint256 lpReturn = 1_980_000e18;

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_invalidDepositAmountsLength() public {
        uint256[] memory minWithdrawAmounts = new uint256[](3);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e18;
        minWithdrawAmounts[2] = 1_000_000e18;

        uint256 lpReturn = 1_980_000e18;

        vm.startPrank(relayer);

        vm.expectRevert("MainnetController/invalid-min-withdraw-amounts");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);

        uint256[] memory minWithdrawAmounts2 = new uint256[](1);
        minWithdrawAmounts[0] = 1_000_000e6;

        vm.expectRevert("MainnetController/invalid-min-withdraw-amounts");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts2);
    }

    function test_removeLiquidityCurve_underAllowableSlippageBoundary() public {
        bytes32 curveDeposit = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDeposit, 4_000_000e18, uint256(4_000_000e18) / 1 days);

        _addLiquidity(2_000_000e6, 2_000_000e18);  // Get more than 2m LP tokens in return

        uint256 lpReturn = 2_000_000e18;  // 2% on 2m

        uint256 minTotalReturned = lpReturn * curvePool.get_virtual_price() * 98/100 / 1e18;

        assertApproxEqAbs(minTotalReturned, 1_960_000e18, 50_000e18);  // Sanity check on precision

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = minTotalReturned / 2 / 1e12;  // Rounding down causes boundary
        minWithdrawAmounts[1] = minTotalReturned / 2;

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);

        minWithdrawAmounts[0] = minTotalReturned / 2 / 1e12 + 1;
        minWithdrawAmounts[1] = minTotalReturned / 2;

        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount() public {
        bytes32 curveWithdraw = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, 0, 0);

        _addLiquidity();

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 499_000e6;
        minWithdrawAmounts[1] = 499_000e18;

        uint256 lpReturn = 1_000_000e18;

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary() public {
        _addLiquidity();

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 499_000e6;
        minWithdrawAmounts[1] = 499_000e18;

        uint256 lpReturn = 1_000_000e18;

        uint256 id = vm.snapshotState();

        // Use a success call to see how many tokens are returned from burning 1e18 LP tokens
        vm.prank(relayer);
        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);

        uint256 totalWithdrawn = withdrawnAmounts[0] * 1e12 + withdrawnAmounts[1];

        vm.revertToState(id);

        bytes32 curveWithdraw = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        // Set to below boundary
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, totalWithdrawn - 1, totalWithdrawn / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);

        // Set to boundary
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, totalWithdrawn, totalWithdrawn / 1 days);

        vm.prank(relayer);
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

}

contract MainnetControllerRemoveLiquiditySuccessTests is CurveTestBase {

    function test_removeLiquidityCurve() public {
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e18);

        uint256 startingPyUsdBalance = rlUsd.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply  = curveLp.totalSupply();

        assertEq(lpTokensReceived, 1_997_612.166757892422937582e18);

        assertEq(rlUsd.balanceOf(address(almProxy)), 0);
        assertEq(rlUsd.balanceOf(CURVE_POOL),        startingPyUsdBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawKey), 3_000_000e18);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 980_000e6;
        minWithdrawAmounts[1] = 980_000e18;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(assetsReceived[0], 1_000_001.487588e6);
        assertEq(assetsReceived[1], 999_998.512248098338560810e18);

        uint256 sumAssetsReceived = assetsReceived[0] * 1e12 + assetsReceived[1];

        assertApproxEqAbs(sumAssetsReceived, 2_000_000e18, 1e18);

        assertEq(usdc.balanceOf(address(almProxy)), assetsReceived[0]);

        assertApproxEqAbs(usdc.balanceOf(CURVE_POOL), startingUsdcBalance - assetsReceived[0], 10e6);  // Fees from other deposits

        assertEq(rlUsd.balanceOf(address(almProxy)), assetsReceived[1]);

        assertApproxEqAbs(rlUsd.balanceOf(CURVE_POOL), startingPyUsdBalance - assetsReceived[1], 10e18);  // Fees from other deposits

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
        assertEq(curveLp.totalSupply(),                startingTotalSupply - lpTokensReceived);

        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawKey), 3_000_000e18 - sumAssetsReceived);
    }

}

contract MainnetControllerSwapCurveFailureTests is CurveTestBase {

    function test_swapCurve_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_slippageNotSet() public {
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset0To1() public {
        _addLiquidity();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e18 - 1);

        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e18);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset1To0() public {
        _addLiquidity();

        deal(RLUSD, address(almProxy), 1_000_000e18);

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6 - 1);

        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_zeroMaxAmount() public {
        bytes32 curveSwap = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwap, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_rateLimitBoundary() public {
        _addLiquidity();

        deal(RLUSD, address(almProxy), 1_000_000e18 + 1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18 + 1, 998_000e6);

        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 998_000e6);
    }

}

contract MainnetControllerSwapCurveSuccessTests is CurveTestBase {

    function test_swapCurve() public {
        _addLiquidity(1_000_000e6, 1_000_000e18);

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%

        uint256 startingPyUsdBalance = rlUsd.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdc.balanceOf(CURVE_POOL);

        deal(RLUSD, address(almProxy), 1_000_000e18);

        assertEq(rlUsd.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(rlUsd.balanceOf(CURVE_POOL),        startingPyUsdBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey), 1_000_000e18);

        vm.prank(relayer);
        uint256 amountOut = mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 999_500e6);

        assertEq(amountOut, 999_726.854240e6);

        assertEq(rlUsd.balanceOf(address(almProxy)), 0);
        assertEq(rlUsd.balanceOf(CURVE_POOL),        startingPyUsdBalance + 1_000_000e18);

        assertEq(usdc.balanceOf(address(almProxy)), amountOut);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance - amountOut);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey), 0);
    }

}

contract MainnetControllerGetVirtualPriceStressTests is CurveTestBase {

    function test_getVirtualPrice_stressTest() public {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(curveDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        vm.stopPrank();

        _addLiquidity(100_000_000e6, 100_000_000e18);

        uint256 virtualPrice1 = curvePool.get_virtual_price();

        assertEq(virtualPrice1, 1.001195343715175271e18);

        deal(address(usdc), address(almProxy), 100_000_000e6);

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 1);  // 1e-16%

        vm.prank(relayer);
        uint256 amountOut = mainnetController.swapCurve(CURVE_POOL, 0, 1, 100_000_000e6, 1000e18);

        assertEq(amountOut, 99_123_484.133360978396763017e18);

        uint256 virtualPrice2 = curvePool.get_virtual_price();

        assertEq(virtualPrice2, 1.001228501012622650e18);
        assertGt(virtualPrice2, virtualPrice1);

        _addLiquidity(0, 100_000_000e18);

        uint256 virtualPrice3 = curvePool.get_virtual_price();

        assertEq(virtualPrice3, 1.001245739473410937e18);
        assertGt(virtualPrice3, virtualPrice2);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1000e6;
        minWithdrawAmounts[1] = 1000e18;

        vm.startPrank(relayer);
        mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            curveLp.balanceOf(address(almProxy)),
            minWithdrawAmounts
        );
        vm.stopPrank();

        uint256 virtualPrice4 = curvePool.get_virtual_price();

        assertEq(virtualPrice4, 1.001245739473435168e18);
        assertGt(virtualPrice4, virtualPrice3);
    }

}

contract MainnetControllerE2ECurveRLUsdUsdcPoolTest is CurveTestBase {

    function test_e2e_addAndRemoveLiquidityCurve() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(RLUSD,         address(almProxy), 1_000_000e18);

        uint256 usdcBalance  = usdc.balanceOf(CURVE_POOL);
        uint256 rlUsdBalance = rlUsd.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e18;

        uint256 minLpAmount = 1_990_000e18;

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(rlUsd.balanceOf(address(almProxy)), 1_000_000e18);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);

        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(rlUsd.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(CURVE_POOL),  usdcBalance  + 1_000_000e6);
        assertEq(rlUsd.balanceOf(CURVE_POOL), rlUsdBalance + 1_000_000e18);

        // Step 2: Swap USDC for RLUSD

        deal(address(usdc), address(almProxy), 100e6);

        assertEq(usdc.balanceOf(address(almProxy)),  100e6);
        assertEq(rlUsd.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 rlUsdReturned = mainnetController.swapCurve(CURVE_POOL, 0, 1, 100e6, 99.9e18);

        assertEq(rlUsdReturned, 99.989998025251364331e18);

        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(rlUsd.balanceOf(address(almProxy)), rlUsdReturned);

        // Step 3: Remove liquidity

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 999_900e6;
        minWithdrawAmounts[1] = 999_900e18;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(assetsReceived[0], 1_000_018.281459e6);
        assertEq(assetsReceived[1], 999_981.719217481940282590e18);

        uint256 sumAssetsReceived = assetsReceived[0] * 1e12 + assetsReceived[1];

        assertEq(sumAssetsReceived, 2_000_000.000676481940282590e18);

        assertEq(usdc.balanceOf(address(almProxy)),  assetsReceived[0]);
        assertEq(rlUsd.balanceOf(address(almProxy)), assetsReceived[1] + rlUsdReturned);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
    }

}

contract MainnetControllerE2ECurveSUsdeSUsdsPoolTest is ForkTestBase {

    address constant CURVE_POOL = 0x3CEf1AFC0E8324b57293a6E7cE663781bbEFBB79;

    IERC20 curveLp = IERC20(CURVE_POOL);

    bytes32 curveDepositKey;
    bytes32 curveSwapKey;
    bytes32 curveWithdrawKey;

    function setUp() public virtual override  {
        super.setUp();

        curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.95e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function test_e2e_addAndRemoveLiquidityCurve() public {
        uint256 susdeAmount = susde.convertToShares(1_000_000e18);
        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susde), address(almProxy), susdeAmount);
        deal(address(susds), address(almProxy), susdsAmount);

        uint256 susdeBalance = susde.balanceOf(CURVE_POOL);
        uint256 susdsBalance = susds.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdeAmount;
        amounts[1] = susdsAmount;

        uint256 minLpAmount = 1_990_000e18;  // 0.5% on 2m

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        assertEq(susde.balanceOf(address(almProxy)), susdeAmount);
        assertEq(susds.balanceOf(address(almProxy)), susdsAmount);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);

        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(susds.balanceOf(address(almProxy)), 0);

        assertEq(susde.balanceOf(CURVE_POOL), susdeBalance + susdeAmount);
        assertEq(susds.balanceOf(CURVE_POOL), susdsBalance + susdsAmount);

        // Step 2: Swap susde for susds

        uint256 susdeSwapAmount = susde.convertToShares(100e18);
        uint256 minSUsdsAmount  = susds.convertToShares(99.5e18);

        deal(address(susde), address(almProxy), susdeSwapAmount);

        assertEq(susde.balanceOf(address(almProxy)), susdeSwapAmount);
        assertEq(susds.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 susdsReturned = mainnetController.swapCurve(CURVE_POOL, 0, 1, susdeSwapAmount, minSUsdsAmount);

        assertEq(susds.convertToAssets(susdsReturned), 99.881093521220159847e18);

        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);

        // Step 3: Remove liquidity

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = susdeAmount * 130/100;
        minWithdrawAmounts[1] = susdsAmount * 65/100;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(susde.convertToAssets(assetsReceived[0]), 1_317_667.897665048206964107e18);
        assertEq(susds.convertToAssets(assetsReceived[1]), 682_834.255232605539287062e18);

        assertEq(
            susde.convertToAssets(assetsReceived[0]) + susds.convertToAssets(assetsReceived[1]),
            2_000_502.152897653746251169e18
        );

        assertEq(susde.balanceOf(address(almProxy)), assetsReceived[0]);
        assertEq(susds.balanceOf(address(almProxy)), assetsReceived[1] + susdsReturned);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
    }

}
