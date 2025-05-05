// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

import { ICurvePoolLike } from "../../src/libraries/CurveLib.sol";

contract CurveTestBase is ForkTestBase {

    address constant CURVE_POOL = 0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85;

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

    function _addLiquidity(uint256 usdcAmount, uint256 usdtAmount)
        internal returns (uint256 lpTokensReceived)
    {
        deal(address(usdc), address(almProxy), usdcAmount);
        deal(address(usdt), address(almProxy), usdtAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = usdtAmount;

        uint256 minLpAmount = (usdcAmount + usdtAmount) * 1e12 * 98/100;

        vm.prank(relayer);
        return mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function _addLiquidity() internal returns (uint256 lpTokensReceived) {
        return _addLiquidity(1_000_000e6, 1_000_000e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

}

contract MainnetControllerAddLiquidityCurveFailureTests is CurveTestBase {

    function test_addLiquidityCurve_notRelayer() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

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
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_invalidDepositAmountsLength() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;
        amounts[2] = 1_000_000e6;

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
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

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
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset0() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6 + 1;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[0] = 1_000_000e6;

        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset1() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6 + 1;

        uint256 minLpAmount = 1_950_000e18;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[1] = 1_000_000e6;

        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

}

contract MainnetControllerAddLiquiditySuccessTests is CurveTestBase {

    function test_addLiquidityCurve() public {
        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        uint256 startingUsdtBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply = curveLp.totalSupply();

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveDepositKey), 2_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey),    1_000_000e18);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(
            CURVE_POOL,
            amounts,
            minLpAmount
        );

        assertEq(lpTokensReceived, 1_987_199.361495730708108741e18);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance + 1_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance + 1_000_000e6);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply + lpTokensReceived);

        // NOTE: A large swap happened because of the balances in the pool being skewed towards USDT.
        assertEq(rateLimits.getCurrentRateLimit(curveDepositKey), 0);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey),    465_022.869727319215817005e18);
    }

    function test_addLiquidityCurve_swapRateLimit() public {
        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.7e18);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 0;

        uint256 minLpAmount = 800_000e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        // NOTE: These values are skewed because pool balance is skewed.
        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 260_000e6;
        minWithdrawnAmounts[1] = 730_000e6;

        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Calculate the average difference between the assets deposited and withdrawn, into an average swap amount
        //         and compare against the derived swap amount

        uint256[] memory rates = ICurvePoolLike(CURVE_POOL).stored_rates();

        uint256 totalSwapped;
        for (uint256 i; i < withdrawnAmounts.length; i++) {
            totalSwapped += _absSubtraction(withdrawnAmounts[i] * rates[i], amounts[i] * rates[i]) / 1e18;
        }
        totalSwapped /= 2;

        // Difference is accurate to within 1 unit of USDC
        assertApproxEqAbs(derivedSwapAmount, totalSwapped, 0.000001e18);

        // Check real values, comparing amount of USDC deposited with amount withdrawn as a result of the "swap"
        assertEq(withdrawnAmounts[0], 265_480.996766e6);
        assertEq(withdrawnAmounts[1], 734_605.036920e6);

        // Some accuracy differences because of fees
        assertEq(derivedSwapAmount,                 734_562.020077130663332756e18);
        assertEq(1_000_000e6 - withdrawnAmounts[0], 734_519.003234e6);
    }

    function testFuzz_addLiquidityCurve_swapRateLimit(uint256 usdcAmount, uint256 usdtAmount) public {
        // Set slippage to be zero and unlimited rate limits for purposes of this test
        // Not using actual unlimited rate limit because need to get swap amount to be reduced.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 1);  // 1e-16%
        rateLimits.setUnlimitedRateLimitData(curveDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        rateLimits.setRateLimitData(curveSwapKey, type(uint256).max - 1, type(uint256).max - 1);
        vm.stopPrank();

        usdcAmount = _bound(usdcAmount, 1_000_000e6, 10_000_000_000e6);
        usdtAmount = _bound(usdtAmount, 1_000_000e6, 10_000_000_000e6);

        deal(address(usdc), address(almProxy), usdcAmount);
        deal(address(usdt), address(almProxy), usdtAmount);

        // Step 1: Add liquidity with fuzzed inputs, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = usdtAmount;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, 1e18);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 1e6;
        minWithdrawnAmounts[1] = 1e6;

        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Calculate the average difference between the assets deposited and withdrawn, into an average swap amount
        //         and compare against the derived swap amount

        uint256[] memory rates = ICurvePoolLike(CURVE_POOL).stored_rates();

        uint256 totalSwapped;
        for (uint256 i; i < withdrawnAmounts.length; i++) {
            totalSwapped += _absSubtraction(withdrawnAmounts[i] * rates[i], amounts[i] * rates[i]) / 1e18;
        }
        totalSwapped /= 2;

        // Difference is accurate to within 1 unit of USDC
        assertApproxEqAbs(derivedSwapAmount, totalSwapped, 0.000001e18);
    }

}

contract MainnetControllerRemoveLiquidityCurveFailureTests is CurveTestBase {

    function test_removeLiquidityCurve_notRelayer() public {
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e6;

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
        minWithdrawAmounts[1] = 1_000_000e6;

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
        minWithdrawAmounts[1] = 1_000_000e6;
        minWithdrawAmounts[2] = 1_000_000e6;

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
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256 minTotalReturned = lpTokensReceived * curvePool.get_virtual_price() * 98/100 / 1e18;

        assertApproxEqAbs(minTotalReturned, 1_960_000e18, 50_000e18);  // Sanity check on precision

        // Skewed pool, using 465k as anchor point because USDC balance of pool is low
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = minTotalReturned / 1e12 - 465_000e6;

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        // Add one to get over the boundary
        minWithdrawAmounts[1] += 1;

        mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount() public {
        bytes32 curveWithdraw = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, 0, 0);

        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary() public {
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        uint256 id = vm.snapshotState();

        // Use a success call to see how many tokens are returned from burning all LP tokens
        vm.prank(relayer);
        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        uint256 totalWithdrawn = (withdrawnAmounts[0] + withdrawnAmounts[1]) * 1e12;

        vm.revertToState(id);

        bytes32 curveWithdraw = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        // Set to below boundary
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, totalWithdrawn - 1, totalWithdrawn / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        // Set to boundary
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdraw, totalWithdrawn, totalWithdrawn / 1 days);

        vm.prank(relayer);
        mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

}

contract MainnetControllerRemoveLiquiditySuccessTests is CurveTestBase {

    function test_removeLiquidityCurve() public {
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256 startingUsdtBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply = curveLp.totalSupply();

        assertEq(lpTokensReceived, 1_987_199.361495730708108741e18);

        assertEq(curveLp.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawKey), 3_000_000e18);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(assetsReceived[0], 465_059.586753e6);
        assertEq(assetsReceived[1], 1_535_013.847298e6);

        uint256 sumAssetsReceived = (assetsReceived[0] + assetsReceived[1]) * 1e12;

        assertApproxEqAbs(sumAssetsReceived, 2_000_000e18, 100e18);

        assertGe(sumAssetsReceived, 2_000_000e18);  // Pool is skewed so more value can be removed after balancing

        assertEq(curveLp.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), assetsReceived[0]);

        assertApproxEqAbs(usdc.balanceOf(CURVE_POOL), startingUsdcBalance - assetsReceived[0], 100e6);  // Fees from other deposits

        assertEq(usdt.balanceOf(address(almProxy)), assetsReceived[1]);

        assertApproxEqAbs(usdt.balanceOf(CURVE_POOL), startingUsdtBalance - assetsReceived[1], 100e6);  // Fees from other deposits

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
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_sameIndex() public {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-indices");
        mainnetController.swapCurve(CURVE_POOL, 1, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_firstIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/index-too-high");
        mainnetController.swapCurve(CURVE_POOL, 2, 0, 1_000_000e6, 980_000e6);

        vm.prank(relayer);
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_secondIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/index-too-high");
        mainnetController.swapCurve(CURVE_POOL, 0, 2, 1_000_000e6, 980_000e6);

        vm.prank(relayer);
        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_slippageNotSet() public {
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset0To1() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6 - 1);

        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset1To0() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6 - 1);

        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_zeroMaxAmount() public {
        bytes32 curveSwap = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(), CURVE_POOL);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwap, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_rateLimitBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdt), address(almProxy), 1_000_000e6 + 1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6 + 1, 998_000e6);

        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 998_000e6);
    }

}

contract MainnetControllerSwapCurveSuccessTests is CurveTestBase {

    function test_swapCurve() public {
        _addLiquidity(1_000_000e6, 1_000_000e6);
        skip(1 days);  // Recharge swap rate limit from deposit

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%

        uint256 startingUsdtBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance = usdc.balanceOf(CURVE_POOL);

        deal(address(usdt), address(almProxy), 1_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey), 1_000_000e18);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        vm.prank(relayer);
        uint256 amountOut = mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 999_500e6);

        assertEq(amountOut, 999_712.1851680e6);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUsdtBalance + 1_000_000e6);

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

        _addLiquidity(100_000_000e6, 100_000_000e6);

        uint256 virtualPrice1 = curvePool.get_virtual_price();

        assertEq(virtualPrice1, 1.006472121147810626e18);

        deal(address(usdc), address(almProxy), 100_000_000e6);

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 1);  // 1e-16%

        // Perform a massive swap to stress the virtual price
        vm.prank(relayer);
        uint256 amountOut = mainnetController.swapCurve(CURVE_POOL, 0, 1, 100_000_000e6, 1000e6);

        assertEq(amountOut, 99_949_401.825058e6);

        // Assert price rises
        uint256 virtualPrice2 = curvePool.get_virtual_price();

        assertEq(virtualPrice2, 1.006481289896618067e18);
        assertGt(virtualPrice2, virtualPrice1);

        // Add one sided liquidity to stress the virtual price
        _addLiquidity(0, 100_000_000e6);

        // Assert price rises
        uint256 virtualPrice3 = curvePool.get_virtual_price();

        assertEq(virtualPrice3, 1.006486607243912047e18);
        assertGt(virtualPrice3, virtualPrice2);

        // Remove liquidity
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1000e6;
        minWithdrawAmounts[1] = 1000e6;

        vm.startPrank(relayer);
        mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            curveLp.balanceOf(address(almProxy)),
            minWithdrawAmounts
        );
        vm.stopPrank();

        // Assert price rises
        uint256 virtualPrice4 = curvePool.get_virtual_price();

        assertEq(virtualPrice4, 1.006486607244205989e18);
        assertGt(virtualPrice4, virtualPrice3);
    }

}

contract MainnetController3PoolSwapRateLimitTest is ForkTestBase {

    // Working in BTC terms because only high TVL active NG three asset pool is BTC
    address CURVE_POOL = 0xabaf76590478F2fE0b396996f55F0b61101e9502;

    IERC20 ebtc = IERC20(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
    IERC20 lbtc = IERC20(0x8236a87084f8B84306f72007F36F2618A5634494);
    IERC20 wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    bytes32 curveDepositKey;
    bytes32 curveSwapKey;
    bytes32 curveWithdrawKey;

    function setUp() public virtual override  {
        super.setUp();

        curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositKey,  5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 5_000_000e18, uint256(5_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.001e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function test_addLiquidityCurve_swapRateLimit() public {
        deal(address(ebtc), address(almProxy), 2_000e8);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e8;
        amounts[1] = 0;
        amounts[2] = 0;

        uint256 minLpAmount = 0.1e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](3);
        minWithdrawnAmounts[0] = 0.01e8;
        minWithdrawnAmounts[1] = 0.01e8;
        minWithdrawnAmounts[2] = 0.01e8;

        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Show "swapped" asset results, demonstrate that the swap rate limit was reduced by the amount
        //         of eBTC that was reduced, 1e8 deposited + ~0.35e8 withdrawn = ~0.65e8 swapped

        assertEq(withdrawnAmounts[0], 0.35689723e8);
        assertEq(withdrawnAmounts[1], 0.22809783e8);
        assertEq(withdrawnAmounts[2], 0.41478858e8);

        // Some accuracy differences because of fees
        assertEq(derivedSwapAmount,         0.642994597417510402e18);
        assertEq(1e8 - withdrawnAmounts[0], 0.64310277e8);
    }

}

contract MainnetControllerSUsdsUsdtSwapRateLimitTest is ForkTestBase {

    address constant CURVE_POOL = 0x00836Fe54625BE242BcFA286207795405ca4fD10;

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
        rateLimits.setRateLimitData(curveDepositKey,  5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 5_000_000e18, uint256(5_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.01e18);

        // Seed the pool with some liquidity to be able to perform the swap

        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);
        deal(address(usdt),  address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 100_000e18;

        vm.prank(relayer);
        mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

    function test_addLiquidityCurve_swapRateLimit() public {
        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 0;

        uint256 minLpAmount = 100_000e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 100_000e18;
        minWithdrawnAmounts[1] = 100_000e6;

        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Show "swapped" asset results, demonstrate that the swap rate limit was reduced by the dollar amount
        //         of sUSDS that was reduced, 1m deposited + ~666k withdrawn = ~333k swapped

        assertEq(susds.convertToAssets(withdrawnAmounts[0]), 666_655.261741191232680640e18);
        assertEq(withdrawnAmounts[1],                        333_327.974363e6);

        // Some accuracy differences because of fees
        assertEq(derivedSwapAmount, 333_336.356311008220852225e18);

        assertEq(1_000_000e18 - susds.convertToAssets(withdrawnAmounts[0]), 333_344.738258808767319360e18);
    }

}

contract MainnetControllerE2ECurveUsdtUsdcPoolTest is CurveTestBase {

    function test_e2e_addSwapAndRemoveLiquidityCurve() public {
        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.95e18);

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256 usdcBalance = usdc.balanceOf(CURVE_POOL);
        uint256 usdtBalance = usdt.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(CURVE_POOL), usdcBalance + 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL), usdtBalance + 1_000_000e6);

        // Step 2: Swap USDT for USDC

        deal(address(usdt), address(almProxy), 100_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 100_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 usdcReturned = mainnetController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturned, 99_984.727700e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        // Step 3: Swap USDT for USDC again (ensure no issues with USDT approval)

        deal(address(usdt), address(almProxy), 100_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);
        assertEq(usdt.balanceOf(address(almProxy)), 100_000e6);

        vm.prank(relayer);
        usdcReturned += mainnetController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturned, 199_967.818973e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);  // Incremented
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        // Step 4: Swap USDC for USDT

        deal(address(usdc), address(almProxy), 100_000e6);  // NOTE: Overwrites balance

        assertEq(usdc.balanceOf(address(almProxy)), 100_000e6);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 usdtReturned = mainnetController.swapCurve(CURVE_POOL, 0, 1, 100_000e6, 99_900e6);

        assertEq(usdtReturned, 100_008.403841e6);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)), usdtReturned);

        // Step 5: Remove liquidity

        usdcBalance = usdc.balanceOf(CURVE_POOL);
        usdtBalance = usdt.balanceOf(CURVE_POOL);

        // NOTE: Asserting to demonstrate that balances are very skewed, so min withdraw amounts have to be as well
        assertEq(usdcBalance, 1_774_134.212373e6);
        assertEq(usdtBalance, 6_285_626.822871e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 440_000e6;
        minWithdrawAmounts[1] = 1_550_000e6;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(assetsReceived[0], 440_250.439766e6);
        assertEq(assetsReceived[1], 1_559_827.329765e6);

        uint256 sumAssetsReceived = assetsReceived[0] + assetsReceived[1];

        assertEq(sumAssetsReceived, 2_000_077.769531e6);

        assertEq(usdc.balanceOf(address(almProxy)), assetsReceived[0]);
        assertEq(usdt.balanceOf(address(almProxy)), assetsReceived[1] + usdtReturned);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        // Approximate because of fees
        assertApproxEqAbs(usdc.balanceOf(CURVE_POOL), usdcBalance - assetsReceived[0], 100e6);
        assertApproxEqAbs(usdt.balanceOf(CURVE_POOL), usdtBalance - assetsReceived[1], 100e6);
    }

}

contract MainnetControllerE2ECurveSUsdsUsdtPoolTest is ForkTestBase {

    address constant CURVE_POOL = 0x00836Fe54625BE242BcFA286207795405ca4fD10;

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
        return 22225000;  // April 8, 2025
    }

    function test_e2e_addSwapAndRemoveLiquidityCurve() public {
        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);
        deal(address(usdt),  address(almProxy), 1_000_000e6);

        uint256 susdsBalance = susds.balanceOf(CURVE_POOL);
        uint256 usdtBalance  = usdt.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), susdsAmount);
        assertEq(usdt.balanceOf(address(almProxy)),  1_000_000e6);

        vm.prank(relayer);
        uint256 lpTokensReceived = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        assertEq(susds.balanceOf(CURVE_POOL), susdsBalance + susdsAmount);
        assertEq(usdt.balanceOf(CURVE_POOL),  usdtBalance + 1_000_000e6);

        // Step 2: Swap USDT for sUSDS

        deal(address(usdt), address(almProxy), 100_000e6);

        uint256 minSUsdsAmount = susds.convertToShares(99_500e18);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  100_000e6);

        vm.prank(relayer);
        uint256 susdsReturned = mainnetController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, minSUsdsAmount);

        assertEq(susds.convertToAssets(susdsReturned), 99_996.989363188047296502e18);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        // Step 3: Swap USDT for sUSDS again (ensure no issue with approval)

        deal(address(usdt), address(almProxy), 100_000e6);

        minSUsdsAmount = susds.convertToShares(99_500e18);

        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);
        assertEq(usdt.balanceOf(address(almProxy)),  100_000e6);

        vm.prank(relayer);
        susdsReturned += mainnetController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, minSUsdsAmount);

        assertEq(susds.convertToAssets(susdsReturned), 199_992.859585323329126373e18);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);  // Incremented
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        // Step 4: Swap sUSDS for USDT

        uint256 susdsSwapAmount = susds.convertToShares(100_000e18);

        deal(address(susds), address(almProxy), susdsSwapAmount);  // NOTE: Overwrites balance

        assertEq(susds.balanceOf(address(almProxy)), susdsSwapAmount);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        vm.prank(relayer);
        uint256 usdtReturned = mainnetController.swapCurve(CURVE_POOL, 0, 1, susdsSwapAmount, 99_500e6);

        assertEq(usdtReturned, 99_999.026465e6);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  usdtReturned);

        // Step 5: Remove liquidity

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = susds.convertToShares(900_000e18);
        minWithdrawAmounts[1] = 1_090_000e6;

        vm.prank(relayer);
        uint256[] memory assetsReceived = mainnetController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertEq(susds.convertToAssets(assetsReceived[0]), 900_005.135097519857743801e18);
        assertEq(assetsReceived[1],                        1_099_999.173746e6);

        assertEq(
            susds.convertToAssets(assetsReceived[0]) + assetsReceived[1] * 1e12,
            2_000_004.308843519857743801e18
        );

        assertEq(susds.balanceOf(address(almProxy)), assetsReceived[0]);
        assertEq(usdt.balanceOf(address(almProxy)),  assetsReceived[1] + usdtReturned);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
    }

}
