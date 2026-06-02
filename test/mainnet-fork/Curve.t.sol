// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICurveFacet } from "../../src/facets/curve/ICurveFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface ICurvePoolLike {

    function calc_token_amount(uint256[] memory amounts, bool is_deposit) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function stored_rates() external view returns (uint256[] memory);

}

abstract contract Curve_TestBase is ForkTestBase {

    address internal constant CURVE_POOL = 0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85;

    IERC20Like internal constant CURVE_LP = IERC20Like(CURVE_POOL);

    bytes32 internal curveAggregateDepositKey;
    bytes32 internal curveDepositUSDCKey;
    bytes32 internal curveDepositUSDTKey;
    bytes32 internal curveSwapUSDCKey;
    bytes32 internal curveSwapUSDTKey;
    bytes32 internal curveAggregateWithdrawKey;
    bytes32 internal curveWithdrawUSDCKey;
    bytes32 internal curveWithdrawUSDTKey;

    function setUp() public virtual override {
        super.setUp();

        curveAggregateDepositKey  = mainnetController.curve_getAggregateDepositRateLimitKey(CURVE_POOL);
        curveDepositUSDCKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(usdc));
        curveDepositUSDTKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(usdt));
        curveSwapUSDCKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(usdc));
        curveSwapUSDTKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(usdt));
        curveAggregateWithdrawKey = mainnetController.curve_getAggregateWithdrawRateLimitKey(CURVE_POOL);
        curveWithdrawUSDCKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(usdc));
        curveWithdrawUSDTKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(usdt));

        vm.startPrank(SPARK_PROXY);

        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.98e18);

        rateLimits.setUnlimitedRateLimitData(curveAggregateDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveDepositUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveDepositUSDTKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapUSDTKey);
        rateLimits.setUnlimitedRateLimitData(curveAggregateWithdrawKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawUSDTKey);

        vm.stopPrank();
    }

    function _addLiquidity(uint256 usdcAmount, uint256 usdtAmount)
        internal
        returns (uint256 shares)
    {
        deal(address(usdc), address(almProxy), usdcAmount);
        deal(address(usdt), address(almProxy), usdtAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = usdtAmount;

        uint256 minShares = (usdcAmount + usdtAmount) * 1e12 * 98/100;

        vm.prank(allocator);
        return mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);
    }

    function _addLiquidity() internal returns (uint256 shares) {
        return _addLiquidity(1_000_000e6, 1_000_000e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

}

contract MainnetController_Curve_AddLiquidity_Tests is Curve_TestBase {

    function setUp() public virtual override {
        super.setUp();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);
    }

    function test_addLiquidityCurve_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.curve_addLiquidity(CURVE_POOL, new uint256[](2), 0);
    }

    function test_addLiquidityCurve_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.curve_addLiquidity(CURVE_POOL, new uint256[](2), 0);
    }

    function test_addLiquidityCurve_virtualPriceZero() external {
        vm.mockCall(
            CURVE_POOL,
            abi.encodeWithSelector(ICurvePoolLike.get_virtual_price.selector),
            abi.encode(0)
        );

        vm.expectRevert("CurveFacet/virtual-price-zero");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, new uint256[](0), 0);
    }

    function test_addLiquidityCurve_invalidDepositAmounts() external {
        vm.expectRevert("CurveFacet/invalid-deposit-amounts");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, new uint256[](3), 0);
    }

    function test_addLiquidityCurve_slippageNotSet() external {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minShares = 1_950_000e18;

        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0);

        vm.expectRevert("CurveFacet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);
    }

    function test_addLiquidityCurve_slippageBoundary() external {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 boundaryAmount = 1_947_406.306381940636380661e18;

        assertApproxEqAbs(boundaryAmount, 1_950_000e18, 50_000e18);  // Sanity check on precision

        vm.expectRevert("CurveFacet/min-shares-too-low");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, boundaryAmount - 1);

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, boundaryAmount);
    }

    function test_addLiquidityCurve_minSharesNotMet() external {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        // Mock first balance check to match the actual expected shares so that the delta shares is 0.
        vm.mockCall(
            CURVE_POOL,
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, address(almProxy)),
            abi.encode(1_987_199.361495730708108741e18)
        );

        vm.expectRevert("CurveFacet/min-shares-not-met");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_zeroMaxAmount_swapAsset0() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_rateLimitBoundary_swapAsset0() external {
        uint256 boundaryAmount = 534_940.413247e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, boundaryAmount - 1, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_zeroMaxAmount_depositAsset0() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDCKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_rateLimitBoundary_depositAsset0() external {
        uint256 boundaryAmount = 465_059.586753e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDCKey, boundaryAmount - 1, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDCKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_zeroMaxAmount_depositAsset1() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDTKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_rateLimitBoundary_depositAsset1() external {
        uint256 boundaryAmount = 1_535_013.847298e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDTKey, boundaryAmount - 1, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositUSDTKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve_zeroMaxAmount_aggregate() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey, 0, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minShares = 1_950_000e18;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);
    }

    function test_addLiquidityCurve_rateLimitBoundary_aggregate() external {
        uint256 boundaryAmount = 465_059.586753e18 + 1_535_013.847298e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey, boundaryAmount - 1, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1_950_000e18);
    }

    function test_addLiquidityCurve() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey, 3_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDCKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDTKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDCKey,         1_000_000e6,  uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDTKey,         1_000_000e6,  uint256(1_000_000e6) / 1 days);
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minShares = ICurvePoolLike(CURVE_POOL).calc_token_amount(amounts, true);

        uint256 startingUSDTBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUSDCBalance = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply = CURVE_LP.totalSupply();

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);
        assertEq(CURVE_LP.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),         1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey),         1_000_000e6);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit ICurveFacet.CurveAddLiquidity(CURVE_POOL, minShares, amounts);

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(
            CURVE_POOL,
            amounts,
            minShares
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, minShares);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance + 1_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance + 1_000_000e6);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), shares);
        assertEq(CURVE_LP.totalSupply(),                startingTotalSupply + shares);

        uint256 usdcSwappedIn  = 534_940.413247e6;
        uint256 usdcDeposited  = 1_000_000e6 - usdcSwappedIn;
        uint256 usdtSwappedOut = 535_013.847298e6;
        uint256 usdtDeposited  = 1_000_000e6 + usdtSwappedOut;

        // Should have used the full aggregate deposit rate limit
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18 - (usdcDeposited + usdtDeposited) * 1e12);

        // Deposit rate limits take into account the actual amounts deposited, not the amounts swapped in.
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey), 2_000_000e6 - usdcDeposited);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey), 2_000_000e6 - usdtDeposited);

        // An imbalance requiring a swapping in of USDC should have reduced the swap rate limit.
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6 - usdcSwappedIn);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);
    }

    function testFuzz_addLiquidityCurve_swapRateLimit(uint256 usdcAmount, uint256 usdtAmount) external {
        // Set slippage to be zero and unlimited rate limits for purposes of this test
        // Not using actual unlimited rate limit because need to get swap amount to be reduced.
        vm.startPrank(SPARK_PROXY);

        mainnetController.curve_setMaxSlippage(CURVE_POOL, 1);  // 1e-16%

        uint256 startingSwapRateLimit = type(uint256).max - 1;

        rateLimits.setRateLimitData(curveSwapUSDCKey, startingSwapRateLimit, 0);
        rateLimits.setRateLimitData(curveSwapUSDTKey, startingSwapRateLimit, 0);

        vm.stopPrank();

        usdcAmount = _bound(usdcAmount, 1_000_000e6, 10_000_000_000e6);
        usdtAmount = _bound(usdtAmount, 1_000_000e6, 10_000_000_000e6);

        deal(address(usdc), address(almProxy), usdcAmount);
        deal(address(usdt), address(almProxy), usdtAmount);

        // Step 1: Add liquidity with fuzzed inputs, check how much the rate limit was reduced.

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = usdcAmount;
        amounts[1] = usdtAmount;

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(CURVE_POOL, amounts, 1e18);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool.

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 1e6;
        minWithdrawnAmounts[1] = 1e6;

        vm.prank(allocator);
        uint256[] memory withdrawnAmounts = mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawnAmounts);

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
            // Some USDT was swapped in and less was actually deposited for the liquidity.
            // Difference is accurate to within 1 unit of USDT
            assertApproxEqAbs(
                rateLimits.getCurrentRateLimit(curveSwapUSDTKey),
                startingSwapRateLimit - (amounts[1] - withdrawnAmounts[1]),
                0.000001e18
            );
        } else {
            // No swapping occurred, the amounts withdrawn should be equal to the amounts deposited.
            assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), startingSwapRateLimit);
            assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), startingSwapRateLimit);
        }
    }

}

contract MainnetController_Curve_RemoveLiquidity_Tests is Curve_TestBase {

    function test_removeLiquidityCurve_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.curve_removeLiquidity(CURVE_POOL, 0, new uint256[](2));
    }

    function test_removeLiquidityCurve_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.curve_removeLiquidity(CURVE_POOL, 0, new uint256[](2));
    }

    function test_removeLiquidityCurve_invalidMinWithdrawAmountsLength() external {
        vm.expectRevert("CurveFacet/invalid-min-withdraw-amounts");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, 0, new uint256[](3));
    }

    function test_removeLiquidityCurve_slippageNotSet() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0);

        vm.expectRevert("CurveFacet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_minAmountNotMet() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        // Mock first balance check to match the actual expected withdrawn amount so that the delta withdrawn amount is 0.
        vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, address(almProxy)),
            abi.encode(465_059.586753e6)
        );

        vm.expectRevert("CurveFacet/min-amount-not-met");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_slippageBoundary() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        // uint256 boundaryAmount = 1_960_052.321513685548416205e18;
        uint256 boundaryAmount = 1_960_052.321514000000000000e18;

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = (boundaryAmount / 1e12) - minWithdrawAmounts[0] - 1;

        vm.expectRevert("CurveFacet/min-amounts-too-low");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);

        minWithdrawAmounts[1] = 1_535_000e6;
        minWithdrawAmounts[0] = (boundaryAmount / 1e12) - minWithdrawAmounts[1] - 1;

        vm.expectRevert("CurveFacet/min-amounts-too-low");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);

        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = (boundaryAmount / 1e12) - minWithdrawAmounts[0];

        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount_aggregate() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, 0, 0);

        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary_aggregate() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        uint256 boundaryAmount = 2_000_073.434051e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, boundaryAmount - 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount_token0() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDCKey, 0, 0);

        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary_token0() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        uint256 boundaryAmount = 465_059.586753e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDCKey, boundaryAmount - 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDCKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_zeroMaxAmount_token1() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey, 0, 0);

        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve_rateLimitBoundary_token1() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        uint256 boundaryAmount = 1_535_013.847298e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey, boundaryAmount - 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawAmounts);
    }

    function test_removeLiquidityCurve() external {
        uint256 shares = _addLiquidity(1_000_000e6, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, 3_000_000e18, 0);
        rateLimits.setRateLimitData(curveWithdrawUSDCKey,      2_000_000e6, 0);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey,      2_000_000e6, 0);
        vm.stopPrank();

        uint256 startingUSDTBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUSDCBalance = usdc.balanceOf(CURVE_POOL);
        uint256 startingTotalSupply = CURVE_LP.totalSupply();

        assertEq(shares, 1_987_199.361495730708108741e18);

        assertEq(CURVE_LP.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), shares);
        assertEq(CURVE_LP.totalSupply(),                startingTotalSupply);

        assertEq(rateLimits.getCurrentRateLimit(curveAggregateWithdrawKey), 3_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawUSDCKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawUSDTKey),      2_000_000e6);

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 465_000e6;
        minWithdrawAmounts[1] = 1_535_000e6;

        uint256[] memory expectedWithdrawnAmounts = new uint256[](2);

        expectedWithdrawnAmounts[0] = 465_059.586753e6;
        expectedWithdrawnAmounts[1] = 1_535_013.847298e6;

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit ICurveFacet.CurveRemoveLiquidity(
            CURVE_POOL,
            shares,
            expectedWithdrawnAmounts
        );

        vm.prank(allocator);
        uint256[] memory assetsReceived = mainnetController.curve_removeLiquidity(
            CURVE_POOL,
            shares,
            minWithdrawAmounts
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(assetsReceived[0], expectedWithdrawnAmounts[0]);
        assertEq(assetsReceived[1], expectedWithdrawnAmounts[1]);

        uint256 aggregateAssetsReceived = (assetsReceived[0] + assetsReceived[1]) * 1e12;

        assertApproxEqAbs(aggregateAssetsReceived, 2_000_000e18, 100e18);

        assertGe(aggregateAssetsReceived, 2_000_000e18);  // Pool is skewed so more value can be removed after balancing

        assertEq(CURVE_LP.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdc.balanceOf(address(almProxy)), assetsReceived[0]);

        assertApproxEqAbs(usdc.balanceOf(CURVE_POOL), startingUSDCBalance - assetsReceived[0], 100e6);  // Fees from other deposits

        assertEq(usdt.balanceOf(address(almProxy)), assetsReceived[1]);

        assertApproxEqAbs(usdt.balanceOf(CURVE_POOL), startingUSDTBalance - assetsReceived[1], 100e6);  // Fees from other deposits

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);
        assertEq(CURVE_LP.totalSupply(),                startingTotalSupply - shares);

        assertEq(rateLimits.getCurrentRateLimit(curveAggregateWithdrawKey), 3_000_000e18 - aggregateAssetsReceived);
        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawUSDCKey),      2_000_000e6 - assetsReceived[0]);
        assertEq(rateLimits.getCurrentRateLimit(curveWithdrawUSDTKey),      2_000_000e6 - assetsReceived[1]);
    }

}

contract MainnetController_Curve_Swap_Tests is Curve_TestBase {

    function setUp() public override {
        super.setUp();

        _addLiquidity(1_000_000e6, 1_000_000e6);

        deal(address(usdt), address(almProxy), 1_000_000e6);
        deal(address(usdc), address(almProxy), 1_000_000e6);
    }

    function test_swapCurve_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.curve_swap(CURVE_POOL, 0, 0, 0, 0);
    }

    function test_swapCurve_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.curve_swap(CURVE_POOL, 0, 0, 0, 0);
    }

    function test_swapCurve_indicesEqual() external {
        vm.expectRevert("CurveFacet/indices-equal");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 1, 0, 0);
    }

    function test_swapCurve_invalidInputIndex() external {
        vm.expectRevert("CurveFacet/invalid-index");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 2, 0, 0, 0);
    }

    function test_swapCurve_invalidOutputIndex() external {
        vm.expectRevert("CurveFacet/invalid-index");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 2, 0, 0);
    }

    function test_swapCurve_zeroMaxAmount_token0() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_rateLimitBoundary_token0() external {
        uint256 boundaryAmount = 1_000_000e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, boundaryAmount - 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDCKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_zeroMaxAmount_token1() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDTKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_rateLimitBoundary_token1() external {
        uint256 boundaryAmount = 1_000_000e6;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDTKey, boundaryAmount - 1, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveSwapUSDTKey, boundaryAmount, 0);

        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_slippageNotSet() external {
        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0);

        vm.expectRevert("CurveFacet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, 980_000e6);
    }

    function test_swapCurve_minAmountTooLow_token0() external {
        uint256 boundaryAmount = 980_000e6;

        vm.expectRevert("CurveFacet/min-amount-too-low");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, boundaryAmount - 1);

        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, boundaryAmount);
    }

    function test_swapCurve_minAmountTooLow_token1() external {
        uint256 boundaryAmount = 980_000e6;

        vm.expectRevert("CurveFacet/min-amount-too-low");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, boundaryAmount - 1);

        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, boundaryAmount);
    }

    function test_swapCurve_minAmountNotMet() external {
        // Mock first balance check to match the actual expected swap out amount so that the delta amount out is 0.
        vm.mockCall(
            address(usdt),
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, address(almProxy)),
            abi.encode(1_000_027.338547e6)
        );

        vm.expectRevert("CurveFacet/min-amount-not-met");
        vm.prank(allocator);
        mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, 999_500e6);
    }

    function test_swapCurve_usdc() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%
        rateLimits.setRateLimitData(curveSwapUSDCKey, 1_000_000e6, 0);
        rateLimits.setRateLimitData(curveSwapUSDTKey, 1_000_000e6, 0);
        vm.stopPrank();

        uint256 startingUSDTBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUSDCBalance = usdc.balanceOf(CURVE_POOL);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit ICurveFacet.CurveSwap(
            CURVE_POOL,
            0,
            1,
            1_000_000e6,
            1_000_027.338547e6
        );

        vm.prank(allocator);
        uint256 amountOut = mainnetController.curve_swap(CURVE_POOL, 0, 1, 1_000_000e6, 999_500e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 1_000_027.338547e6);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6 + amountOut);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance - amountOut);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance + 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 0);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);
    }

    function test_swapCurve_usdt() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.999e18);  // 0.1%
        rateLimits.setRateLimitData(curveSwapUSDCKey, 1_000_000e6, 0);
        rateLimits.setRateLimitData(curveSwapUSDTKey, 1_000_000e6, 0);
        vm.stopPrank();

        uint256 startingUSDTBalance = usdt.balanceOf(CURVE_POOL);
        uint256 startingUSDCBalance = usdc.balanceOf(CURVE_POOL);

        deal(address(usdt), address(almProxy), 1_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit ICurveFacet.CurveSwap(
            CURVE_POOL,
            1,
            0,
            1_000_000e6,
            999_712.1851680e6
        );

        vm.prank(allocator);
        uint256 amountOut = mainnetController.curve_swap(CURVE_POOL, 1, 0, 1_000_000e6, 999_500e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(amountOut, 999_712.1851680e6);

        assertEq(usdc.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy), CURVE_POOL), 0);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(CURVE_POOL),        startingUSDTBalance + 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6 + amountOut);
        assertEq(usdc.balanceOf(CURVE_POOL),        startingUSDCBalance - amountOut);

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 0);
    }

}

contract MainnetController_Curve_AddLiquidity_Swap_Comparison_Tests is Curve_TestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey, 3_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDCKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDTKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDCKey,         1_000_000e6,  uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDTKey,         1_000_000e6,  uint256(1_000_000e6) / 1 days);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);
    }

    function test_addLiquidity_unbalanced() external {
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),         1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey),         1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(
            CURVE_POOL,
            amounts,
            1_980_000e18
        );

        assertEq(shares, 1_987_199.361495730708108741e18);

        uint256 usdcSwappedIn  = 534_940.413247e6;
        uint256 usdcDeposited  = 1_000_000e6 - usdcSwappedIn;
        uint256 usdtSwappedOut = 535_013.847298e6;
        uint256 usdtDeposited  = 1_000_000e6 + usdtSwappedOut;

        // Should have used the full aggregate deposit rate limit
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18 - (usdcDeposited + usdtDeposited) * 1e12);

        // Deposit rate limits take into account the actual amounts deposited, not the amounts swapped in.
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey), 2_000_000e6 - usdcDeposited);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey), 2_000_000e6 - usdtDeposited);

        // An imbalance requiring a swapping in of USDC should have reduced the swap rate limit.
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6 - usdcSwappedIn);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);
    }

    function test_swap_addLiquidity_balanced() external {
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey),      2_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey),         1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey),         1_000_000e6);

        uint256 usdcSwappedIn = 534_940.413247e6;

        vm.prank(allocator);
        uint256 usdtSwappedOut = mainnetController.curve_swap(CURVE_POOL, 0, 1, usdcSwappedIn, 530_000e6);

        assertEq(usdtSwappedOut, 535_010.321202e6);  // 535_013.847298e6

        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6 - 534_940.413247e6);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6);

        uint256 usdcDeposit = 1_000_000e6 - usdcSwappedIn;
        uint256 usdtDeposit = 1_000_000e6 + usdtSwappedOut;

        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = usdcDeposit;
        depositAmounts[1] = usdtDeposit;

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(
            CURVE_POOL,
            depositAmounts,
            1_980_000e18
        );

        assertEq(shares, 1_987_194.788667540577155178e18);

        uint256 extraUSDTSwapIn = 0.798579e6; // a small additional swap in performed compared to unbalanced add liquidity test

        uint256 actualUSDCDeposit = usdcDeposit + 0.798465e6; // a small additional swap out performed compared to unbalanced add liquidity test
        uint256 actualUSDTDeposit = usdtDeposit - extraUSDTSwapIn;

        // Should have used the full aggregate deposit rate limit
        assertEq(rateLimits.getCurrentRateLimit(curveAggregateDepositKey), 3_000_000e18 - (actualUSDCDeposit + actualUSDTDeposit) * 1e12);

        // Deposit rate limits take into account the actual amounts deposited, not the amounts swapped in.
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDCKey), 2_000_000e6 - actualUSDCDeposit);
        assertEq(rateLimits.getCurrentRateLimit(curveDepositUSDTKey), 2_000_000e6 - actualUSDTDeposit);

        // An imbalance requiring a swapping in of USDC should have reduced the swap rate limit.
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDCKey), 1_000_000e6 - usdcSwappedIn);
        assertEq(rateLimits.getCurrentRateLimit(curveSwapUSDTKey), 1_000_000e6 - extraUSDTSwapIn);
    }

}

contract MainnetController_Curve_GetVirtualPrice_StressTests is Curve_TestBase {

    function test_getVirtualPrice_stressTest() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(curveAggregateDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveDepositUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveDepositUSDTKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapUSDTKey);
        rateLimits.setUnlimitedRateLimitData(curveAggregateWithdrawKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawUSDCKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawUSDTKey);
        vm.stopPrank();

        _addLiquidity(100_000_000e6, 100_000_000e6);

        uint256 virtualPrice1 = ICurvePoolLike(CURVE_POOL).get_virtual_price();

        assertEq(virtualPrice1, 1.006472121147810626e18);

        deal(address(usdc), address(almProxy), 100_000_000e6);

        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 1);  // 1e-16%

        // Perform a massive swap to stress the virtual price
        vm.prank(allocator);
        uint256 amountOut = mainnetController.curve_swap(CURVE_POOL, 0, 1, 100_000_000e6, 1000e6);

        assertEq(amountOut, 99_949_401.825058e6);

        // Assert price rises
        uint256 virtualPrice2 = ICurvePoolLike(CURVE_POOL).get_virtual_price();

        assertEq(virtualPrice2, 1.006481289896618067e18);
        assertGt(virtualPrice2, virtualPrice1);

        // Add one sided liquidity to stress the virtual price
        _addLiquidity(0, 100_000_000e6);

        // Assert price rises
        uint256 virtualPrice3 = ICurvePoolLike(CURVE_POOL).get_virtual_price();

        assertEq(virtualPrice3, 1.006486607243912047e18);
        assertGt(virtualPrice3, virtualPrice2);

        // Remove liquidity
        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = 1000e6;
        minWithdrawAmounts[1] = 1000e6;

        vm.startPrank(allocator);
        mainnetController.curve_removeLiquidity(
            CURVE_POOL,
            CURVE_LP.balanceOf(address(almProxy)),
            minWithdrawAmounts
        );
        vm.stopPrank();

        // Assert price rises
        uint256 virtualPrice4 = ICurvePoolLike(CURVE_POOL).get_virtual_price();

        assertEq(virtualPrice4, 1.006486607244205989e18);
        assertGt(virtualPrice4, virtualPrice3);
    }

}

contract MainnetController_Curve_3Pool_Tests is ForkTestBase {

    // Working in BTC terms because only high TVL active NG three asset pool is BTC
    address internal CURVE_POOL = 0xabaf76590478F2fE0b396996f55F0b61101e9502;

    IERC20Like internal ebtc = IERC20Like(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
    IERC20Like internal lbtc = IERC20Like(0x8236a87084f8B84306f72007F36F2618A5634494);
    IERC20Like internal wbtc = IERC20Like(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    bytes32 internal curveAggregateDepositKey;
    bytes32 internal curveEBTCDepositKey;
    bytes32 internal curveLBTCDepositKey;
    bytes32 internal curveWBTCDeositKey;
    bytes32 internal curveSwapEBTCKey;
    bytes32 internal curveSwapLBTCKey;
    bytes32 internal curveSwapWBTCKey;
    bytes32 internal curveAggregateWithdrawKey;
    bytes32 internal curveWithdrawEBTCKey;
    bytes32 internal curveWithdrawLBTCKey;
    bytes32 internal curveWithdrawWBTCKey;

    function setUp() public virtual override {
        super.setUp();

        curveAggregateDepositKey  = mainnetController.curve_getAggregateDepositRateLimitKey(CURVE_POOL);
        curveEBTCDepositKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(ebtc));
        curveLBTCDepositKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(lbtc));
        curveWBTCDeositKey        = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(wbtc));
        curveSwapEBTCKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(ebtc));
        curveSwapLBTCKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(lbtc));
        curveSwapWBTCKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(wbtc));
        curveAggregateWithdrawKey = mainnetController.curve_getAggregateWithdrawRateLimitKey(CURVE_POOL);
        curveWithdrawEBTCKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(ebtc));
        curveWithdrawLBTCKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(lbtc));
        curveWithdrawWBTCKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(wbtc));

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey,  5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveEBTCDepositKey,       5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveLBTCDepositKey,       5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveWBTCDeositKey,        5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveSwapEBTCKey,          5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveSwapLBTCKey,          5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveSwapWBTCKey,          5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, 5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawEBTCKey,      5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawLBTCKey,      5_000_000e8,  uint256(5_000_000e8) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawWBTCKey,      5_000_000e8,  uint256(5_000_000e8) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.001e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function test_addLiquidityCurve_swapRateLimit() external {
        deal(address(ebtc), address(almProxy), 2_000e8);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e8;
        amounts[1] = 0;
        amounts[2] = 0;

        uint256 minShares = 0.1e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapEBTCKey);

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapEBTCKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](3);
        minWithdrawnAmounts[0] = 0.01e8;
        minWithdrawnAmounts[1] = 0.01e8;
        minWithdrawnAmounts[2] = 0.01e8;

        vm.prank(allocator);
        uint256[] memory withdrawnAmounts = mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawnAmounts);

        // Step 3: Show "swapped" asset results, demonstrate that the swap rate limit was reduced by the amount
        //         of eBTC that was reduced, 1e8 deposited + ~0.35e8 withdrawn = ~0.65e8 swapped

        assertEq(withdrawnAmounts[0], 0.35689723e8);
        assertEq(withdrawnAmounts[1], 0.22809783e8);
        assertEq(withdrawnAmounts[2], 0.41478858e8);

        assertEq(derivedSwapAmount,         0.64310277e8);
        assertEq(1e8 - withdrawnAmounts[0], 0.64310277e8);
    }

}

contract MainnetController_Curve_SUSDS_USDT_Pool_Tests is ForkTestBase {

    address internal constant CURVE_POOL = 0x00836Fe54625BE242BcFA286207795405ca4fD10;

    IERC20Like internal CURVE_LP = IERC20Like(CURVE_POOL);

    bytes32 internal curveAggregateDepositKey;
    bytes32 internal curveSUSDSDepositKey;
    bytes32 internal curveDepositUSDTKey;
    bytes32 internal curveSwapSUSDSKey;
    bytes32 internal curveSwapUSDTKey;
    bytes32 internal curveAggregateWithdrawKey;
    bytes32 internal curveWithdrawSUSDSKey;
    bytes32 internal curveWithdrawUSDTKey;

    function setUp() public virtual override {
        super.setUp();

        curveAggregateDepositKey  = mainnetController.curve_getAggregateDepositRateLimitKey(CURVE_POOL);
        curveSUSDSDepositKey      = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(susds));
        curveDepositUSDTKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(usdt));
        curveSwapSUSDSKey         = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(susds));
        curveSwapUSDTKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(usdt));
        curveAggregateWithdrawKey = mainnetController.curve_getAggregateWithdrawRateLimitKey(CURVE_POOL);
        curveWithdrawSUSDSKey     = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(susds));
        curveWithdrawUSDTKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(usdt));

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey,  5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSUSDSDepositKey,      5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDTKey,       5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapSUSDSKey,         5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDTKey,          5_000_000e6,  uint256(5_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, 5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawSUSDSKey,     5_000_000e18, uint256(5_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey,      5_000_000e6,  uint256(5_000_000e6) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.01e18);

        // Seed the pool with some liquidity to be able to perform the swap

        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);
        deal(address(usdt),  address(almProxy), 1_000_000e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 1_000_000e6;

        uint256 minShares = 100_000e18;

        vm.prank(allocator);
        mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

    function test_addLiquidityCurve_swapRateLimit() external {
        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);

        // Step 1: Add liquidity, check how much the rate limit was reduced

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 0;

        uint256 minShares = 100_000e18;

        uint256 startingRateLimit = rateLimits.getCurrentRateLimit(curveSwapSUSDSKey);

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);

        uint256 derivedSwapAmount = startingRateLimit - rateLimits.getCurrentRateLimit(curveSwapSUSDSKey);

        // Step 2: Withdraw full balance of LP tokens, withdrawing proportional amounts from the pool

        uint256[] memory minWithdrawnAmounts = new uint256[](2);
        minWithdrawnAmounts[0] = 100_000e18;
        minWithdrawnAmounts[1] = 100_000e6;

        vm.prank(allocator);
        uint256[] memory withdrawnAmounts = mainnetController.curve_removeLiquidity(CURVE_POOL, shares, minWithdrawnAmounts);

        // Step 3: Show "swapped" asset results, demonstrate that the swap rate limit was reduced by the dollar amount
        //         of sUSDS that was reduced, 1m deposited + ~666k withdrawn = ~333k swapped

        assertEq(susds.convertToAssets(withdrawnAmounts[0]), 666_655.261741191232680640e18);
        assertEq(withdrawnAmounts[1],                        333_327.974363e6);

        assertEq(derivedSwapAmount,                 318_439.244889314469602262e18);
        assertEq(susdsAmount - withdrawnAmounts[0], 318_439.244889314469602262e18);
    }

}

contract MainnetController_Curve_USDT_USDC_Pool_E2ETests is Curve_TestBase {

    function test_e2e_addSwapAndRemoveLiquidityCurve() external {
        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.95e18);

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        uint256 usdcBalance = usdc.balanceOf(CURVE_POOL);
        uint256 usdtBalance = usdt.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000e6;
        amounts[1] = 1_000_000e6;

        uint256 minShares = 1_950_000e18;

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdt.balanceOf(address(almProxy)), 1_000_000e6);

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), shares);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        assertEq(usdc.balanceOf(CURVE_POOL), usdcBalance + 1_000_000e6);
        assertEq(usdt.balanceOf(CURVE_POOL), usdtBalance + 1_000_000e6);

        // Step 2: Swap USDT for USDC

        deal(address(usdt), address(almProxy), 100_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 100_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        vm.prank(allocator);
        uint256 usdcReturned = mainnetController.curve_swap(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturned, 99_984.727700e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        // Step 3: Swap USDT for USDC again (ensure no issues with USDT approval)

        deal(address(usdt), address(almProxy), 100_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);
        assertEq(usdt.balanceOf(address(almProxy)), 100_000e6);

        vm.prank(allocator);
        usdcReturned += mainnetController.curve_swap(CURVE_POOL, 1, 0, 100_000e6, 99_900e6);

        assertEq(usdcReturned, 199_967.818973e6);

        assertEq(usdc.balanceOf(address(almProxy)), usdcReturned);  // Incremented
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        // Step 4: Swap USDC for USDT

        deal(address(usdc), address(almProxy), 100_000e6);  // NOTE: Overwrites balance

        assertEq(usdc.balanceOf(address(almProxy)), 100_000e6);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        vm.prank(allocator);
        uint256 usdtReturned = mainnetController.curve_swap(CURVE_POOL, 0, 1, 100_000e6, 99_900e6);

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

        vm.prank(allocator);
        uint256[] memory assetsReceived = mainnetController.curve_removeLiquidity(
            CURVE_POOL,
            shares,
            minWithdrawAmounts
        );

        assertEq(assetsReceived[0], 440_250.439766e6);
        assertEq(assetsReceived[1], 1_559_827.329765e6);

        uint256 sumAssetsReceived = assetsReceived[0] + assetsReceived[1];

        assertEq(sumAssetsReceived, 2_000_077.769531e6);

        assertEq(usdc.balanceOf(address(almProxy)), assetsReceived[0]);
        assertEq(usdt.balanceOf(address(almProxy)), assetsReceived[1] + usdtReturned);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);

        // Approximate because of fees
        assertApproxEqAbs(usdc.balanceOf(CURVE_POOL), usdcBalance - assetsReceived[0], 100e6);
        assertApproxEqAbs(usdt.balanceOf(CURVE_POOL), usdtBalance - assetsReceived[1], 100e6);
    }

}

contract MainnetController_Curve_SUSDS_USDT_Pool_E2ETests is ForkTestBase {

    address internal constant CURVE_POOL = 0x00836Fe54625BE242BcFA286207795405ca4fD10;

    IERC20Like internal CURVE_LP = IERC20Like(CURVE_POOL);

    bytes32 internal curveAggregateDepositKey;
    bytes32 internal curveSUSDSDepositKey;
    bytes32 internal curveDepositUSDTKey;
    bytes32 internal curveSwapSUSDSKey;
    bytes32 internal curveSwapUSDTKey;
    bytes32 internal curveAggregateWithdrawKey;
    bytes32 internal curveWithdrawSUSDSKey;
    bytes32 internal curveWithdrawUSDTKey;

    function setUp() public virtual override {
        super.setUp();

        curveAggregateDepositKey  = mainnetController.curve_getAggregateDepositRateLimitKey(CURVE_POOL);
        curveSUSDSDepositKey      = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(susds));
        curveDepositUSDTKey       = mainnetController.curve_getAssetDepositRateLimitKey(CURVE_POOL, address(usdt));
        curveSwapSUSDSKey         = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(susds));
        curveSwapUSDTKey          = mainnetController.curve_getSwapRateLimitKey(CURVE_POOL, address(usdt));
        curveAggregateWithdrawKey = mainnetController.curve_getAggregateWithdrawRateLimitKey(CURVE_POOL);
        curveWithdrawSUSDSKey     = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(susds));
        curveWithdrawUSDTKey      = mainnetController.curve_getAssetWithdrawRateLimitKey(CURVE_POOL, address(usdt));

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveAggregateDepositKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSUSDSDepositKey,      2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveDepositUSDTKey,       2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapSUSDSKey,         1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapUSDTKey,          1_000_000e6,  uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(curveAggregateWithdrawKey, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawSUSDSKey,     2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawUSDTKey,      2_000_000e6,  uint256(2_000_000e6) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.curve_setMaxSlippage(CURVE_POOL, 0.95e18);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22225000;  // April 8, 2025
    }

    function test_e2e_addSwapAndRemoveLiquidityCurve() external {
        uint256 susdsAmount = susds.convertToShares(1_000_000e18);

        deal(address(susds), address(almProxy), susdsAmount);
        deal(address(usdt),  address(almProxy), 1_000_000e6);

        uint256 susdsBalance = susds.balanceOf(CURVE_POOL);
        uint256 usdtBalance  = usdt.balanceOf(CURVE_POOL);

        // Step 1: Add liquidity

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = susdsAmount;
        amounts[1] = 1_000_000e6;

        uint256 minShares = 1_950_000e18;

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), susdsAmount);
        assertEq(usdt.balanceOf(address(almProxy)),  1_000_000e6);

        vm.prank(allocator);
        uint256 shares = mainnetController.curve_addLiquidity(CURVE_POOL, amounts, minShares);

        assertEq(CURVE_LP.balanceOf(address(almProxy)), shares);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        assertEq(susds.balanceOf(CURVE_POOL), susdsBalance + susdsAmount);
        assertEq(usdt.balanceOf(CURVE_POOL),  usdtBalance + 1_000_000e6);

        // Step 2: Swap USDT for sUSDS

        deal(address(usdt), address(almProxy), 100_000e6);

        uint256 minSUSDSAmount = susds.convertToShares(99_500e18);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  100_000e6);

        vm.prank(allocator);
        uint256 susdsReturned = mainnetController.curve_swap(CURVE_POOL, 1, 0, 100_000e6, minSUSDSAmount);

        assertEq(susds.convertToAssets(susdsReturned), 99_996.989363188047296502e18);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        // Step 3: Swap USDT for sUSDS again (ensure no issue with approval)

        deal(address(usdt), address(almProxy), 100_000e6);

        minSUSDSAmount = susds.convertToShares(99_500e18);

        assertEq(susds.balanceOf(address(almProxy)), susdsReturned);
        assertEq(usdt.balanceOf(address(almProxy)),  100_000e6);

        vm.prank(allocator);
        susdsReturned += mainnetController.curve_swap(CURVE_POOL, 1, 0, 100_000e6, minSUSDSAmount);

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

        vm.prank(allocator);
        uint256 usdtReturned = mainnetController.curve_swap(CURVE_POOL, 0, 1, susdsSwapAmount, 99_500e6);

        assertEq(usdtReturned, 99_999.026465e6);

        assertEq(susds.allowance(address(almProxy), CURVE_POOL), 0);
        assertEq(usdt.allowance(address(almProxy),  CURVE_POOL), 0);

        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  usdtReturned);

        // Step 5: Remove liquidity

        uint256[] memory minWithdrawAmounts = new uint256[](2);
        minWithdrawAmounts[0] = susds.convertToShares(900_000e18);
        minWithdrawAmounts[1] = 1_090_000e6;

        vm.prank(allocator);
        uint256[] memory assetsReceived = mainnetController.curve_removeLiquidity(
            CURVE_POOL,
            shares,
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

        assertEq(CURVE_LP.balanceOf(address(almProxy)), 0);
    }

}
