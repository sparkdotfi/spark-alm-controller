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
        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey),    1_000_000e18);

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
        assertEq(rateLimits.getCurrentRateLimit(curveSwapKey),    999_998.512329762328287296e18);  // Small swap occurs on deposit
    }

    function test_addLiquidityCurve_swapRateLimit() public {
        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.001e18);

        deal(address(usdc), address(almProxy), 2_000_000e6);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2_000_000e6;
        amounts[1] = 0;

        uint256 minLpAmount = 1_000_000e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 500_000e6;
        minWithdrawnAmounts[1] = 500_000e18;

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
        assertEq(withdrawnAmounts[0], 1_167_803.429987e6);
        assertEq(withdrawnAmounts[1], 831_961.163091701652224522e18);

        // Some accuracy differences because of fees
        assertEq(derivedSwapAmount,                 832_078.866551978168996427e18);
        assertEq(2_000_000e6 - withdrawnAmounts[0], 832_196.570013e6);
    }

    function testFuzz_addLiquidityCurve_swapRateLimit(uint256 usdcAmount, uint256 rlUsdAmount) public {
        // Set slippage to be zero and unlimited rate limits for purposes of this test
        // Not using actual unlimited rate limit because need to get swap amount to be reduced.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 1);  // 1e-16%
        rateLimits.setUnlimitedRateLimitData(curveDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        rateLimits.setRateLimitData(curveSwapKey, type(uint256).max - 1, type(uint256).max - 1);
        vm.stopPrank();

        usdcAmount  = _bound(usdcAmount,  1_000_000e6,  10_000_000_000e6);
        rlUsdAmount = _bound(rlUsdAmount, 1_000_000e18, 10_000_000_000e18);

        deal(address(usdc), address(almProxy), usdcAmount);
        deal(RLUSD,         address(almProxy), rlUsdAmount);

        // Step 1: Add liquidity with fuzzed inputs, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = rlUsdAmount;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, 1e18);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 1e6;
        minWithdrawnAmounts[1] = 1e18;

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

    function test_swapCurve_sameIndex() public {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-indices");
        mainnetController.swapCurve(CURVE_POOL, 1, 1, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_firstIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(RLUSD, address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/index-too-high");
        mainnetController.swapCurve(CURVE_POOL, 2, 0, 1_000_000e18, 980_000e6);

        vm.prank(relayer);
        mainnetController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e18, 980_000e6);
    }

    function test_swapCurve_secondIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/index-too-high");
        mainnetController.swapCurve(CURVE_POOL, 0, 2, 1_000_000e6, 980_000e18);

        vm.prank(relayer);
        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e18);
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
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/min-amount-not-met");
        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e18 - 1);

        mainnetController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e18);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset1To0() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

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
        skip(1 days);  // Recharge swap rate limit from deposit

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
        skip(1 days);  // Recharge swap rate limit from deposit

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

        // Perform a massive swap to stress the virtual price
        vm.prank(relayer);
        uint256 amountOut = mainnetController.swapCurve(CURVE_POOL, 0, 1, 100_000_000e6, 1000e18);

        assertEq(amountOut, 99_123_484.133360978396763017e18);

        // Assert price rises
        uint256 virtualPrice2 = curvePool.get_virtual_price();

        assertEq(virtualPrice2, 1.001228501012622650e18);
        assertGt(virtualPrice2, virtualPrice1);

        // Add one sided liquidity to stress the virtual price
        _addLiquidity(0, 100_000_000e18);

        // Assert price rises
        uint256 virtualPrice3 = curvePool.get_virtual_price();

        assertEq(virtualPrice3, 1.001245739473410937e18);
        assertGt(virtualPrice3, virtualPrice2);

        // Remove liquidity
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

        // Assert price rises
        uint256 virtualPrice4 = curvePool.get_virtual_price();

        assertEq(virtualPrice4, 1.001245739473435168e18);
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

contract MainnetControllerSUsdeSUsdsSwapRateLimitTest is ForkTestBase {

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
        rateLimits.setRateLimitData(curveDepositKey,  5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 5_000_000e18, uint256(5_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.01e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function test_addLiquidityCurve_swapRateLimit() public {
        uint256 susdeAmount = susde.convertToShares(1_000_000e18);

        deal(address(susde), address(almProxy), susdeAmount);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdeAmount;
        amounts[1] = 0;

        uint256 minLpAmount = 100_000e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapKey);

        vm.startPrank(relayer);

        uint256 lpTokens = mainnetController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 100_000e18;
        minWithdrawnAmounts[1] = 100_000e18;

        uint256[] memory withdrawnAmounts = mainnetController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Show "swapped" asset results, demonstrate that the swap rate limit was reduced by the dollar amount
        //         of sUSDe that was reduced, 1m deposited + ~850k withdrawn = ~150k swapped

        assertEq(susde.convertToAssets(withdrawnAmounts[0]), 850_583.458247970197966075e18);
        assertEq(susds.convertToAssets(withdrawnAmounts[1]), 148_671.435052597244493444e18);

        // Some accuracy differences because of fees
        assertEq(derivedSwapAmount, 149_043.988402313523216974e18);

        assertEq(1_000_000e18 - susde.convertToAssets(withdrawnAmounts[0]), 149_416.541752029802033925e18);
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
