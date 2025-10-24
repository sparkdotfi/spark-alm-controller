// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract AaveV3BaseMarketTestBase is ForkTestBase {

    address constant ATOKEN_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant POOL        = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    IAToken ausdc = IAToken(ATOKEN_USDC);

    uint256 startingAUSDCBalance;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Base.SPARK_EXECUTOR);

        // NOTE: Hit SUPPLY_CAP_EXCEEDED when using 25m
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDC
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            1_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        foreignController.setMaxSlippage(ATOKEN_USDC, 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();

        startingAUSDCBalance = usdcBase.balanceOf(address(ausdc));
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22841965;  // November 24, 2024
    }

}

contract AaveV3BaseMarketDepositFailureTests is AaveV3BaseMarketTestBase {

    function test_depositAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e18);
    }

    function test_depositAave_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.depositAave(makeAddr("fake-token"), 1e18);
    }

    function test_depositAave_zeroMaxSlippage() external {
        vm.prank(Base.SPARK_EXECUTOR);
        foreignController.setMaxSlippage(ATOKEN_USDC, 0);

        vm.prank(relayer);
        vm.expectRevert("ForeignController/max-slippage-not-set");
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6 + 1);

        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_depositAave_usdcSlippageBoundary() external {
        deal(Base.USDC, address(almProxy), 1_000_000e6);

        // Positive slippage because of no rounding error
        // 1e6 * 1_000_000e6 / 1e18 = 1
        // (1e6 - 1) * 1_000_000e6 / 1e18 = 0
        vm.prank(Base.SPARK_EXECUTOR);
        foreignController.setMaxSlippage(ATOKEN_USDC, 1e18 + 1e6);

        vm.prank(relayer);
        vm.expectRevert("ForeignController/slippage-too-high");
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);

        vm.prank(Base.SPARK_EXECUTOR);
        foreignController.setMaxSlippage(ATOKEN_USDC, 1e18 + 1e6 - 1);

        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);
    }

}

contract AaveV3BaseMarketDepositSuccessTests is AaveV3BaseMarketTestBase {

    function test_depositAave_usdc() public {
        deal(Base.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdcBase.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance);

        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);

        assertEq(usdcBase.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)),    1_000_000e6);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 1_000_000e6);
    }

}

contract AaveV3BaseMarketWithdrawFailureTests is AaveV3BaseMarketTestBase {

    function test_withdrawAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.withdrawAave(ATOKEN_USDC, 1_000_000e18);
    }

    function test_withdrawAave_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                foreignController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            0,
            0
        );
        vm.stopPrank();

        deal(Base.USDC, address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);

        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.withdrawAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_withdrawAave_usdcRateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 2_000_000e6);

        // Warp to get past rate limit
        vm.startPrank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);
        skip(1 days);
        foreignController.depositAave(ATOKEN_USDC, 100_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawAave(ATOKEN_USDC, 1_000_000e6 + 1);

        foreignController.withdrawAave(ATOKEN_USDC, 1_000_000e6);
    }

}

contract AaveV3BaseMarketWithdrawSuccessTests is AaveV3BaseMarketTestBase {

    function test_withdrawAave_usdc() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );

        // NOTE: Using lower amount to not hit rate limit
        deal(Base.USDC, address(almProxy), 500_000e6);
        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 500_000e6);

        skip(1 hours);

        uint256 aTokenBalance = ausdc.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 500_009.705892e6);  // Earn some interest

        assertEq(ausdc.balanceOf(address(almProxy)),    aTokenBalance);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 500_000e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 500_000e6 + uint256(1_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 1_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)),    aTokenBalance - (400_000e6 - 1));  // Rounding
        assertEq(usdcBase.balanceOf(address(almProxy)), 400_000e6);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 100_000e6);  // 500k - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 600_000e6);

        // Withdraw all
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance - 400_000e6 + 1);  // Rounding

        assertEq(ausdc.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), aTokenBalance + 1);  // Rounding
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 500_000e6 - aTokenBalance - 1);  // Rounding

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  1_000_000e6);  // Maxes out at 1m
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 1_000_000e6 - aTokenBalance - 1);  // Rounding

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usdcBase.balanceOf(address(ausdc)), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            foreignController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Base.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = ausdc.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_015.893506e6);  // Earn some interest

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, uint256(1_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(ausdc.balanceOf(address(almProxy)),     aTokenBalance);
        assertEq(usdcBase.balanceOf(address(almProxy)),  0);
        assertEq(usdcBase.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        // Full withdraw
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(ausdc.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 1_000_000e6 - aTokenBalance);
    }

}
