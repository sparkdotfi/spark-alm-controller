// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { MockERC20Decimals } from "../mocks/Mocks.sol";

import { ICurveFacet } from "../../src/facets/curve/ICurveFacet.sol";

import { ICurvePoolLike as ICurvePoolLikeLib } from "../../src/facets/curve/CurveFacet.sol";

import { ForkTestBase, ERC20Mock } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

}

interface ICurvePoolLike is ICurvePoolLikeLib {

    function calc_token_amount(uint256[] memory amounts, bool is_deposit) external view returns (uint256);

    function calc_withdraw_one_coin(uint256 amount, int128 index) external view returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

}

abstract contract Curve_TestBase is ForkTestBase {

    // TODO: replace with real target pool once available
    address constant CURVE_POOL = 0xa9D6867C347B8b5f395B8421FB31710B8Fb21a16; // USDC/cgUSD
    address constant CGUSD      = 0xCa72827a3D211CfD8F6b00Ac98824872b72CAb49;

    IERC20Like curveLp = IERC20Like(CURVE_POOL);
    IERC20Like cgUSD   = IERC20Like(CGUSD);

    ICurvePoolLike curvePool = ICurvePoolLike(CURVE_POOL);

    bytes32 curveAggregateDepositKey;
    bytes32 curveUSDCDepositKey;
    bytes32 curveCGUSDDepositKey;
    bytes32 curveSwapUSDCKey;
    bytes32 curveSwapCGUSDKey;
    bytes32 curveWithdrawKey;

    uint256 maxSlippage;

    function setUp() public virtual override {
        super.setUp();

        // There is something weird with the CGUSD token that causes deal to under/overflow.
        // Make a mock Decimal 6 token and replace it for these tests
        uint256 curveCGUSDBalance = cgUSD.balanceOf(CURVE_POOL);

        ERC20Mock mockCgUSD = ERC20Mock(address(new MockERC20Decimals("cgUSD", "cgUSD", 6)));

        vm.etch(CGUSD, address(mockCgUSD).code);

        // Preserve the balance of the CGUSD token in the pool
        deal(address(cgUSD), CURVE_POOL, curveCGUSDBalance);

        if (curveCGUSDBalance < 100_000_000e6 || usdcBase.balanceOf(CURVE_POOL) < 100_000_000e6) {
            // boost liquidity to help later tests
            uint256 amount = 100_000_000e6;
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = amount;
            amounts[1] = amount;

            deal(address(usdcBase), address(this), amount);
            deal(address(cgUSD),    address(this), amount);

            usdcBase.approve(CURVE_POOL, amount);
            cgUSD.approve(CURVE_POOL,    amount);

            ICurvePoolLike(CURVE_POOL).add_liquidity(amounts, 1e18, address(this));
        }

        curveAggregateDepositKey = foreignController.getCurveAggregateDepositRateLimitKey(CURVE_POOL);
        curveUSDCDepositKey      = foreignController.getCurveAssetDepositRateLimitKey(CURVE_POOL, address(usdcBase));
        curveCGUSDDepositKey     = foreignController.getCurveAssetDepositRateLimitKey(CURVE_POOL, address(cgUSD));
        curveSwapUSDCKey         = foreignController.getCurveSwapRateLimitKey(CURVE_POOL, address(usdcBase));
        curveSwapCGUSDKey        = foreignController.getCurveSwapRateLimitKey(CURVE_POOL, address(cgUSD));
        curveWithdrawKey         = foreignController.getCurveWithdrawRateLimitKey(CURVE_POOL);

        vm.startPrank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveAggregateDepositKey, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveUSDCDepositKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveCGUSDDepositKey,     2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDCKey,         1_000_000e6,  uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapCGUSDKey,        1_000_000e6,  uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey,         3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        maxSlippage = 0.98e18;
        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, maxSlippage);

        _labelAddresses();
    }

    function _labelAddresses() internal {
        vm.label(address(usdcBase), "UsdcBase");
        vm.label(CGUSD,             "CgUSD");
        vm.label(CURVE_POOL,        "CurvePool");
    }

    function _addLiquidity(uint256 usdcAmount, uint256 cgUSDAmount)
        internal returns (uint256 lpTokensReceived)
    {
        deal(address(usdcBase), address(almProxy), usdcAmount);
        deal(address(cgUSD),    address(almProxy), cgUSDAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = cgUSDAmount;

        uint256 minLpAmount = (usdcAmount + cgUSDAmount) * 1e12 * 98 / 100;

        vm.prank(relayer);
        lpTokensReceived = foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
        return lpTokensReceived;
    }

    function _addLiquidity() internal returns (uint256 lpTokensReceived) {
        return _addLiquidity(1_000_000e6, 1_000_000e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 36918285;  // Oct 16, 2025 02:45:17 PM +UTC
    }

    function _calcMinWithdrawAmounts(uint256 lpBurnAmount) internal view returns (uint256[] memory) {
        uint256[] memory rates = curvePool.stored_rates();
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        uint256 totalSupply = curveLp.totalSupply();
        uint256 virtualPrice = curvePool.get_virtual_price();

        // Calculate the minimum required total value based on slippage
        // This matches CurveFacet: valueMinWithdrawn >= lpBurnAmount * virtualPrice * maxSlippage / 1e36
        // After the /1e18 normalization in CurveFacet, this gives us the min value in 18 decimals
        uint256 minRequiredValue = lpBurnAmount * virtualPrice * maxSlippage / 1e36; // in 18 decimal precision

        // Calculate expected withdrawal amounts proportionally
        uint256[] memory expectedAmounts = new uint256[](2);
        uint256 totalExpectedValue = 0;

        for (uint256 i = 0; i < 2; i++) {
            expectedAmounts[i] = curvePool.balances(i) * lpBurnAmount / totalSupply;
            totalExpectedValue += expectedAmounts[i] * rates[i];
        }
        totalExpectedValue /= 1e18; // Normalize to 18 decimals to match CurveFacet

        // Distribute the minimum required value proportionally across tokens
        // Add 1 to each amount to compensate for rounding errors and ensure we're at/above the boundary
        for (uint256 i = 0; i < 2; i++) {
            minWithdrawAmounts[i] = expectedAmounts[i] * minRequiredValue / totalExpectedValue + 1;
        }

        return minWithdrawAmounts;
    }

}

contract ForeignController_Curve_AddLiquidity_FailureTests is Curve_TestBase {

    function test_addLiquidityCurve_notRelayer() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_slippageNotSet() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("CurveFacet/max-slippage-not-set");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_invalidDepositAmountsLength() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;
        amounts[2] = 1_000_000e6;
        amounts[3] = 0;
        amounts[4] = 0;

        uint256 minLpAmount = 0;

        vm.startPrank(relayer);

        vm.expectRevert("CurveFacet/invalid-deposit-amounts");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        uint256[] memory amounts2 = new uint256[](1);
        amounts[0] = 1_000_000e6;

        vm.expectRevert("CurveFacet/invalid-deposit-amounts");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts2, minLpAmount);
    }

    function test_addLiquidityCurve_underAllowableSlippageBoundary() public {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 boundaryAmount = 2_000_000e18 * 0.98e18 / curvePool.get_virtual_price();

        assertApproxEqAbs(boundaryAmount, 1_950_000e18, 50_000e18);  // Sanity check on precision

        uint256 minLpAmount = boundaryAmount - 1;

        vm.startPrank(relayer);
        vm.expectRevert("CurveFacet/min-amount-not-met");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        minLpAmount = boundaryAmount;

        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_zeroMaxAmount_aggregate() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveAggregateDepositKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_zeroMaxAmount_usdc() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveUSDCDepositKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_zeroMaxAmount_cgUSD() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveCGUSDDepositKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset0() public {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        amounts[0] = 1_000_000e6 + 1;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[0] = 1_000_000e6;

        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

    function test_addLiquidityCurve_rateLimitBoundaryAsset1() public {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        amounts[1] = 1_000_000e6 + 1;

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        amounts[1] = 1_000_000e6;

        foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);
    }

}

contract ForeignController_Curve_AddLiquidity_SuccessTests is Curve_TestBase {

    function test_addLiquidityCurve() public {
        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        uint256 startingCgUSDBalance = cgUSD.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdcBase.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply  = curveLp.totalSupply();

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        assertEq(usdcBase.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(cgUSD.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 2_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveUSDCDepositKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveCGUSDDepositKey),     2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),         1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey),        1_000_000e6);

        vm.expectEmit(address(foreignController));
        emit ICurveFacet.CurveAddLiquidity(
            CURVE_POOL,
            minLpAmount,
            (amounts[0] + amounts[1]) * 1e12,
            amounts
        );

        vm.prank(relayer);
        uint256 lpTokensReceived = foreignController.addLiquidityCurve(
            CURVE_POOL,
            amounts,
            minLpAmount
        );

        assertEq(lpTokensReceived, minLpAmount);

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance + 1_000_000e6);

        assertEq(cgUSD.balanceOf(address(almProxy)), 0);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance + 1_000_000e6);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply + lpTokensReceived);

        uint256 usdcSwappedIn   = 43.255831e6;
        uint256 usdcDeposited   = 1_000_000e6 - usdcSwappedIn;
        uint256 cgUSDSwappedOut = 43.234104e6;
        uint256 cgUSDDeposited  = 1_000_000e6 + cgUSDSwappedOut;

        // Should have used the full aggregate deposit rate limit
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 0);

        // Deposit rate limits take into account the actual amounts deposited, not the amounts swapped in.
        assertEq(rateLimits.getCurrentRateLimit(curveUSDCDepositKey),  2_000_000e6 - usdcDeposited);
        assertEq(rateLimits.getCurrentRateLimit(curveCGUSDDepositKey), 2_000_000e6 - cgUSDDeposited);

        // An imbalance requiring a swapping in of USDC should have reduced the swap rate limit.
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  1_000_000e6 - usdcSwappedIn);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), 1_000_000e6); // swap out does not affect swap rate limit
    }

    function testFuzz_addLiquidityCurve_swapRateLimit(uint256 usdcAmount, uint256 cgUSDAmount) public {
        // Set slippage to be zero and unlimited rate limits for purposes of this test
        // Not using actual unlimited rate limit because need to get swap amount to be reduced.
        vm.startPrank(SPARK_EXECUTOR);

        foreignController.setCurveMaxSlippage(CURVE_POOL, 1);

        rateLimits.setUnlimitedRateLimitData(curveAggregateDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveUSDCDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveCGUSDDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);

        uint256 startingSwapRateLimit = type(uint256).max - 1;

        rateLimits.setRateLimitData(curveSwapUSDCKey,  startingSwapRateLimit, 0);
        rateLimits.setRateLimitData(curveSwapCGUSDKey, startingSwapRateLimit, 0);

        vm.stopPrank();

        usdcAmount  = _bound(usdcAmount , 1_000_000e6, 10_000_000_000e6);
        cgUSDAmount = _bound(cgUSDAmount, 1_000_000e6, 10_000_000_000e6);

        deal(address(usdcBase), address(almProxy), usdcAmount);
        deal(address(cgUSD),    address(almProxy), cgUSDAmount);

        // Step 1: Add liquidity with fuzzed inputs, check how much the rate limit was reduced.

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = cgUSDAmount;

        vm.startPrank(relayer);
        uint256 lpTokens = foreignController.addLiquidityCurve(CURVE_POOL, amounts, 1e18);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool.

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 1e6;
        minWithdrawnAmounts[1] = 1e6;

        uint256[] memory withdrawnAmounts = foreignController.removeLiquidityCurve(CURVE_POOL, lpTokens, minWithdrawnAmounts);

        // Step 3: Calculate the amounts swapped in based on the amounts withdrawn (which should be close to the amounts deposited).

        if (amounts[0] > withdrawnAmounts[0]) {
            // Some USDC was swapped in and less was actually deposited for the liquidity.
            // Difference is accurate to within 1 unit of USDC
            assertApproxEqAbs(
                rateLimits.getCurrentRateLimit(curveSwapUSDCKey),
                startingSwapRateLimit - (amounts[0] - withdrawnAmounts[0]),
                0.000001e18
            );
        } else if (amounts[1] > withdrawnAmounts[1]) {
            // Some cgUSD was swapped in and less was actually deposited for the liquidity.
            // Difference is accurate to within 1 unit of cgUSD
            assertApproxEqAbs(
                rateLimits.getCurrentRateLimit(curveSwapCGUSDKey),
                startingSwapRateLimit - (amounts[1] - withdrawnAmounts[1]),
                0.000001e18
            );
        } else {
            // No swapping occurred, the amounts withdrawn should be equal to the amounts deposited.
            assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  startingSwapRateLimit);
            assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), startingSwapRateLimit);
        }
    }

}

contract ForeignController_Curve_RemoveLiquidity_FailureTests is Curve_TestBase {

    function test_removeLiquidityCurve_notRelayer() public {
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e6;

        uint256 lpReturn = 1_980_000e18;

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_slippageNotSet() public {
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e6;

        uint256 lpReturn = 1_980_000e18;

        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("CurveFacet/max-slippage-not-set");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_invalidDepositAmountsLength() public {
        uint256[] memory minWithdrawAmounts = new uint256[](3);
        minWithdrawAmounts[0] = 1_000_000e6;
        minWithdrawAmounts[1] = 1_000_000e6;
        minWithdrawAmounts[2] = 1_000_000e6;

        uint256 lpReturn = 1_980_000e18;

        vm.startPrank(relayer);

        vm.expectRevert("CurveFacet/invalid-min-withdraw-amounts");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts);

        uint256[] memory minWithdrawAmounts2 = new uint256[](1);
        minWithdrawAmounts[0] = 1_000_000e6;

        vm.expectRevert("CurveFacet/invalid-min-withdraw-amounts");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpReturn, minWithdrawAmounts2);
    }

    function test_removeLiquidityCurve_underAllowableSlippageBoundary() public {
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256 minTotalReturned = lpTokensReceived * curvePool.get_virtual_price() * 98/100 / 1e18;

        assertApproxEqAbs(minTotalReturned, 1_960_000e18, 50_000e18);  // Sanity check on precision

        // Get boundary amounts, then subtract to go below boundary (should fail)
        uint256[] memory minWithdrawAmounts = _calcMinWithdrawAmounts(lpTokensReceived);
        minWithdrawAmounts[0] -= 100;

        vm.startPrank(relayer);
        vm.expectRevert("CurveFacet/min-amount-not-met");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        // Add back to get to the boundary (should succeed)
        minWithdrawAmounts[0] += 100;

        foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveWithdrawKey, 0, 0);

        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = _calcMinWithdrawAmounts(lpTokensReceived);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary() public {
        uint256 lpTokensReceived = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = _calcMinWithdrawAmounts(lpTokensReceived);

        uint256 id = vm.snapshotState();

        // Use a success call to see how many tokens are returned from burning all LP tokens
        vm.prank(relayer);
        uint256[] memory withdrawnAmounts = foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        uint256 totalWithdrawn = (withdrawnAmounts[0] + withdrawnAmounts[1]) * 1e12;

        vm.revertToState(id);

        // Set to below boundary
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveWithdrawKey, totalWithdrawn - 1, totalWithdrawn / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);

        // Set to boundary
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveWithdrawKey, totalWithdrawn, totalWithdrawn / 1 days);

        vm.prank(relayer);
        foreignController.removeLiquidityCurve(CURVE_POOL, lpTokensReceived, minWithdrawAmounts);
    }

}

contract ForeignController_Curve_RemoveLiquidity_SuccessTests is Curve_TestBase {

    function test_removeLiquidityCurve() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;
        uint256 lpTokensEstimated = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);
        uint256 lpTokensReceived  = _addLiquidity(amounts[0], amounts[1]);

        uint256 startingCgUSDBalance = cgUSD.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdcBase.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply  = curveLp.totalSupply();

        assertEq(lpTokensEstimated, lpTokensReceived, "Estimated LP amount does not match received LP tokens");

        assertEq(curveLp.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(cgUSD.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);
        assertEq(curveLp.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawKey), 3_000_000e18);

        uint256[] memory minWithdrawAmounts = _calcMinWithdrawAmounts(lpTokensReceived);

        uint256[] memory rates = ICurvePoolLike(CURVE_POOL).stored_rates();

        uint256[] memory expectedWithdrawnAmounts = new uint256[](2);

        expectedWithdrawnAmounts[0] = 999_956.744169e6;
        expectedWithdrawnAmounts[1] = 1_000_043.234104e6;

        vm.expectEmit(address(foreignController));
        emit ICurveFacet.CurveRemoveLiquidity(
            CURVE_POOL,
            lpTokensReceived,
            (expectedWithdrawnAmounts[0] + expectedWithdrawnAmounts[1]) * 1e12,
            expectedWithdrawnAmounts
        );

        vm.prank(relayer);
        uint256[] memory assetsReceived = foreignController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        assertGe(assetsReceived[0], minWithdrawAmounts[0], "wrong index 0 amount received");
        assertGe(assetsReceived[1], minWithdrawAmounts[1], "wrong index 1 amount received");

        uint256 sumAssetsReceived = assetsReceived[0] + assetsReceived[1];

        assertGe(sumAssetsReceived, minWithdrawAmounts[0] + minWithdrawAmounts[1], "sum of assets received is less than min withdraw amounts");

        assertEq(curveLp.allowance(address(almProxy), CURVE_POOL), 0, "allowance is not 0");

        assertEq(usdcBase.balanceOf(address(almProxy)), assetsReceived[0], "wrong ALM proxy USDC balance");

        assertEq(cgUSD.balanceOf(address(almProxy)), assetsReceived[1], "wrong ALM proxy cgUSD balance");

        assertEq(curveLp.balanceOf(address(almProxy)), 0, "ALM proxy LP balance is not 0");
        assertEq(curveLp.totalSupply(),                startingTotalSupply - lpTokensReceived, "LP total supply is not correct");

        uint256 calcValueWithdrawn;
        for (uint256 i; i < rates.length; i++) {
            calcValueWithdrawn += rates[i] * assetsReceived[i];
        }
        calcValueWithdrawn /= 1e18;
        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawKey) + calcValueWithdrawn, 3_000_000e18, "rate limit is not correct");
    }

}

contract ForeignController_Curve_Swap_FailureTests is Curve_TestBase {

    function test_swapCurve_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_sameIndex() public {
        vm.prank(relayer);
        vm.expectRevert("CurveFacet/invalid-indices");
        foreignController.swapCurve(CURVE_POOL, 1, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_firstIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(cgUSD), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("CurveFacet/index-too-high");
        foreignController.swapCurve(CURVE_POOL, 4, 0, 1_000_000e6, 980_000e6);

        vm.prank(relayer);
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_secondIndexTooHighBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdcBase), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("CurveFacet/index-too-high");
        foreignController.swapCurve(CURVE_POOL, 0, 4, 1_000_000e6, 980_000e6);

        vm.prank(relayer);
        foreignController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_slippageNotSet() public {
        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0);

        vm.prank(relayer);
        vm.expectRevert("CurveFacet/max-slippage-not-set");
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset0To1() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(usdcBase), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("CurveFacet/min-amount-not-met");
        foreignController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6 - 1);

        foreignController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_underAllowableSlippageBoundaryAsset1To0() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(cgUSD), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("CurveFacet/min-amount-not-met");
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6 - 1);

        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_zeroMaxAmount_usdc() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveSwapUSDCKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.swapCurve(CURVE_POOL, 0, 1, 980_000e6, 1_000_000e6);
    }

    function test_swapCurve_zeroMaxAmount_cgUSD() public {
        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(curveSwapCGUSDKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_rateLimitBoundary() public {
        _addLiquidity();
        skip(1 days);  // Recharge swap rate limit from deposit

        deal(address(cgUSD), address(almProxy), 1_000_000e6 + 1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6 + 1, 998_000e6);

        foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, 998_000e6);
    }

}

contract ForeignController_Curve_Swap_SuccessTests is Curve_TestBase {

    function test_swapCurve_usdc() public {
        _addLiquidity(1_000_000e6, 1_000_000e6);
        skip(1 days);  // Recharge swap rate limit from deposit

        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%

        uint256 startingCgUSDBalance = cgUSD.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdcBase.balanceOf(CURVE_POOL);

        deal(address(usdcBase), address(almProxy), 1_000_000e6);

        assertEq(cgUSD.balanceOf(address(almProxy)), 0);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance);

        assertEq(usdcBase.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), 1_000_000e6);

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        // Calculate expected swap output dynamically
        uint256 expectedAmountOut = curvePool.get_dy(0, 1, 1_000_000e6);

        // Calculate minAmountOut to pass CurveFacet slippage check
        // CurveFacet requires: minAmountOut >= amountIn * rateIn * maxSlippage / rateOut / 1e18
        uint256[] memory rates = curvePool.stored_rates();
        uint256 minAmountOut = 1_000_000e6 * rates[0] * 0.999e18 / rates[1] / 1e18;

        vm.expectEmit(address(foreignController));
        emit ICurveFacet.CurveSwap(CURVE_POOL, 0, 1, 1_000_000e6, expectedAmountOut);

        vm.prank(relayer);
        uint256 amountOut = foreignController.swapCurve(CURVE_POOL, 0, 1, 1_000_000e6, minAmountOut);

        assertEq(amountOut, expectedAmountOut);

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        assertEq(cgUSD.balanceOf(address(almProxy)), amountOut);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance - amountOut);

        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance + 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  0);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), 1_000_000e6);
    }

    function test_swapCurve_cgUSD() public {
        _addLiquidity(1_000_000e6, 1_000_000e6);
        skip(1 days);  // Recharge swap rate limit from deposit

        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%

        uint256 startingCgUSDBalance = cgUSD.balanceOf(CURVE_POOL);
        uint256 startingUsdcBalance  = usdcBase.balanceOf(CURVE_POOL);

        deal(address(cgUSD), address(almProxy), 1_000_000e6);

        assertEq(cgUSD.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance);

        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), 1_000_000e6);

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        // Calculate expected swap output dynamically
        uint256 expectedAmountOut = curvePool.get_dy(1, 0, 1_000_000e6);

        // Calculate minAmountOut to pass CurveFacet slippage check
        // CurveFacet requires: minAmountOut >= amountIn * rateIn * maxSlippage / rateOut / 1e18
        uint256[] memory rates = curvePool.stored_rates();
        uint256 minAmountOut = 1_000_000e6 * rates[1] * 0.999e18 / rates[0] / 1e18;

        vm.expectEmit(address(foreignController));
        emit ICurveFacet.CurveSwap(CURVE_POOL, 1, 0, 1_000_000e6, expectedAmountOut);

        vm.prank(relayer);
        uint256 amountOut = foreignController.swapCurve(CURVE_POOL, 1, 0, 1_000_000e6, minAmountOut);

        assertEq(amountOut, expectedAmountOut);

        assertEq(usdcBase.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(cgUSD.allowance(address(almProxy),    CURVE_POOL), 0);

        assertEq(cgUSD.balanceOf(address(almProxy)), 0);
        assertEq(cgUSD.balanceOf(CURVE_POOL),        startingCgUSDBalance + 1_000_000e6);

        assertEq(usdcBase.balanceOf(address(almProxy)), amountOut);
        assertEq(usdcBase.balanceOf(CURVE_POOL),        startingUsdcBalance - amountOut);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),  1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapCGUSDKey), 0);
    }

}

contract ForeignController_Curve_GetVirtualPrice_StressTests is Curve_TestBase {

    function test_getVirtualPrice_stressTest() public {
        vm.startPrank(SPARK_EXECUTOR);
        rateLimits.setUnlimitedRateLimitData(curveAggregateDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveUSDCDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveCGUSDDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapCGUSDKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        vm.stopPrank();

        _addLiquidity(100_000_000e6, 100_000_000e6);

        uint256 virtualPrice1 = curvePool.get_virtual_price();

        // Verify initial virtual price is reasonable (pool may have slight imbalance from setup)
        assertApproxEqRel(virtualPrice1, 1.020385339110137837e18, 0.01e18);  // Within 1%

        deal(address(usdcBase), address(almProxy), 100_000_000e6);

        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 1);  // 1e-16%

        // Calculate expected swap output dynamically
        uint256 expectedAmountOut = curvePool.get_dy(0, 1, 100_000_000e6);

        // Perform a massive swap to stress the virtual price
        vm.prank(relayer);
        uint256 amountOut = foreignController.swapCurve(CURVE_POOL, 0, 1, 100_000_000e6, 1000e6);

        assertEq(amountOut, expectedAmountOut);

        // Assert price rises
        uint256 virtualPrice2 = curvePool.get_virtual_price();

        assertGt(virtualPrice2, virtualPrice1);

        // Add one sided liquidity to stress the virtual price
        uint256 totalSupplyBefore = curveLp.totalSupply();
        _addLiquidity(0, 100_000_000e6);
        uint256 totalSupplyAfter = curveLp.totalSupply();

        // Calculate expected virtual price based on the value added and LP tokens minted
        // virtualPrice = totalPoolValue / totalSupply
        // New expected price = (oldPrice * oldSupply + valueAdded) / (oldSupply + newLPTokens)
        uint256[] memory rates = curvePool.stored_rates();
        uint256 valueAdded = 100_000_000e6 * rates[1] / 1e18;  // cgUSD value in 18 decimals

        uint256 expectedVirtualPrice3 = (virtualPrice2 * totalSupplyBefore + valueAdded * 1e18) / totalSupplyAfter;

        uint256 virtualPrice3 = curvePool.get_virtual_price();

        // Assert the calculated virtual price matches expectation (within small tolerance for rounding)
        assertApproxEqRel(virtualPrice3, expectedVirtualPrice3, 0.001e18);  // Within 0.1%
        assertGt(virtualPrice3, virtualPrice2);

        // Remove liquidity
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1000e6;
        minWithdrawAmounts[1] = 1000e6;

        vm.startPrank(relayer);
        foreignController.removeLiquidityCurve(
            CURVE_POOL,
            curveLp.balanceOf(address(almProxy)),
            minWithdrawAmounts
        );
        vm.stopPrank();

        // Assert price rises after liquidity removal (due to fees being distributed to remaining LP holders)
        uint256 virtualPrice4 = curvePool.get_virtual_price();

        // Virtual price should continue to increase slightly due to fee distribution
        assertGt(virtualPrice4, virtualPrice3);
    }

}

contract ForeignController_Curve_E2E_CgUSDUsdcBasePool_Test is Curve_TestBase {

    function test_e2e_addSwapAndRemoveLiquidityCurve() public {
        // Set a higher slippage to allow for successes
        vm.prank(SPARK_EXECUTOR);
        foreignController.setCurveMaxSlippage(CURVE_POOL, 0.95e18);

        deal(address(usdcBase), address(almProxy), 1_000_000e6);
        deal(address(cgUSD),    address(almProxy), 1_000_000e6);

        uint256 initialUsdcBalance  = usdcBase.balanceOf(CURVE_POOL);
        uint256 initialCgUSDBalance = cgUSD.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minLpAmount = 1_950_000e18;

        assertEq(curveLp.balanceOf(address(almProxy)), 0);

        assertEq(usdcBase.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(cgUSD.balanceOf(address(almProxy)),    1_000_000e6);

        vm.prank(relayer);
        uint256 lpTokensReceived = foreignController.addLiquidityCurve(CURVE_POOL, amounts, minLpAmount);

        assertEq(curveLp.balanceOf(address(almProxy)), lpTokensReceived);

        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(cgUSD.balanceOf(address(almProxy)),    0);

        assertEq(usdcBase.balanceOf(CURVE_POOL), initialUsdcBalance + 1_000_000e6);
        assertEq(cgUSD.balanceOf(CURVE_POOL),    initialCgUSDBalance + 1_000_000e6);

        // Step 2: Swap cgUSD for USDC

        deal(address(cgUSD), address(almProxy), 100_000e6);

        assertEq(cgUSD.balanceOf(address(almProxy)),    100_000e6);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);

        // Calculate expected output dynamically using Curve's get_dy function
        uint256 expectedUsdcOut1 = curvePool.get_dy(1, 0, 100_000e6);

        vm.prank(relayer);
        uint256 usdcReturned = foreignController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturned, expectedUsdcOut1);

        assertEq(usdcBase.balanceOf(address(almProxy)), usdcReturned);
        assertEq(cgUSD.balanceOf(address(almProxy)),    0);

        // Step 3: Swap cgUSD for USDC again (ensure no issues with approval)

        deal(address(cgUSD), address(almProxy), 100_000e6);

        assertEq(usdcBase.balanceOf(address(almProxy)), usdcReturned);
        assertEq(cgUSD.balanceOf(address(almProxy)),    100_000e6);

        // Calculate expected output for second swap (pool state has changed after first swap)
        uint256 expectedUsdcOut2 = curvePool.get_dy(1, 0, 100_000e6);

        vm.prank(relayer);
        uint256 usdcReturnedFromSwap2 = foreignController.swapCurve(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturnedFromSwap2, expectedUsdcOut2);

        usdcReturned += usdcReturnedFromSwap2;

        assertEq(usdcBase.balanceOf(address(almProxy)), usdcReturned);  // Incremented
        assertEq(cgUSD.balanceOf(address(almProxy)),    0);

        // Step 4: Swap USDC for cgUSD

        deal(address(usdcBase), address(almProxy), 100_000e6);  // NOTE: Overwrites balance

        assertEq(usdcBase.balanceOf(address(almProxy)), 100_000e6);
        assertEq(cgUSD.balanceOf(address(almProxy)),    0);

        // Calculate expected output for swap in opposite direction
        uint256 expectedCgUsdOut = curvePool.get_dy(0, 1, 100_000e6);

        vm.prank(relayer);
        uint256 cgUSDReturned = foreignController.swapCurve(CURVE_POOL, 0, 1, 100_000e6, 99_900e6);

        assertEq(cgUSDReturned, expectedCgUsdOut);

        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(cgUSD.balanceOf(address(almProxy)),    cgUSDReturned);

        // Step 5: Remove liquidity

        // Calculate expected pool balances after all swaps:
        // - Started with: initial + 1M from add liquidity
        // - Swap 1: +100k cgUSD, -expectedUsdcOut1 USDC
        // - Swap 2: +100k cgUSD, -expectedUsdcOut2 USDC
        // - Swap 3: +100k USDC, -expectedCgUsdOut cgUSD
        uint256 expectedUsdcBalance  = initialUsdcBalance + 1_000_000e6 - expectedUsdcOut1 - expectedUsdcOut2 + 100_000e6;
        uint256 expectedCgUsdBalance = initialCgUSDBalance + 1_000_000e6 + 100_000e6 + 100_000e6 - expectedCgUsdOut;

        assertEq(usdcBase.balanceOf(CURVE_POOL), expectedUsdcBalance);
        assertEq(cgUSD.balanceOf(CURVE_POOL),    expectedCgUsdBalance);

        // Calculate minimum withdraw amounts dynamically based on current pool state
        uint256[] memory minWithdrawAmounts = _calcMinWithdrawAmounts(lpTokensReceived);

        vm.prank(relayer);
        uint256[] memory assetsReceived = foreignController.removeLiquidityCurve(
            CURVE_POOL,
            lpTokensReceived,
            minWithdrawAmounts
        );

        // Verify we received at least the minimum amounts
        assertGe(assetsReceived[0], minWithdrawAmounts[0]);
        assertGe(assetsReceived[1], minWithdrawAmounts[1]);

        // Verify the total value received is reasonable (approximately 2M USD worth)
        uint256 sumAssetsReceived = assetsReceived[0] + assetsReceived[1];
        assertApproxEqAbs(sumAssetsReceived, 2_000_000e6, 100_000e6, "wrong assets received");

        assertEq(usdcBase.balanceOf(address(almProxy)), assetsReceived[0]);
        assertEq(cgUSD.balanceOf(address(almProxy)),    assetsReceived[1] + cgUSDReturned);

        assertEq(curveLp.balanceOf(address(almProxy)), 0);
    }

}
