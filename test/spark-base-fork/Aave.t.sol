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
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDC
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            1_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

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

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6 + 1);

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
            RateLimitHelpers.makeAssetKey(
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
        bytes32 key = RateLimitHelpers.makeAssetKey(
            foreignController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );

        // NOTE: Using lower amount to not hit rate limit
        deal(Base.USDC, address(almProxy), 500_000e6);
        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 500_000e6);

        skip(1 days);

        uint256 fullBalance = ausdc.balanceOf(address(almProxy));

        assertGe(fullBalance, 500_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)),    fullBalance);
        assertEq(usdcBase.balanceOf(address(almProxy)), 0);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 500_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)),    fullBalance - 400_000e6 - 1);
        assertEq(usdcBase.balanceOf(address(almProxy)), 400_000e6);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 100_000e6);  // 500k - 400k

        assertEq(rateLimits.getCurrentRateLimit(key), 600_000e6);

        // Withdraw all
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, type(uint256).max), fullBalance - 400_000e6 - 1);

        assertEq(ausdc.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), fullBalance - 1);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 500_000e6 - fullBalance + 1);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6 - fullBalance + 1);

        // Interest accrued was withdrawn, reducing cash balance
        assertLe(usdcBase.balanceOf(address(ausdc)), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() public {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            foreignController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setUnlimitedRateLimitData(key);

        deal(Base.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        foreignController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 days);

        uint256 fullBalance = ausdc.balanceOf(address(almProxy));

        assertGe(fullBalance, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);

        assertEq(ausdc.balanceOf(address(almProxy)),     fullBalance);
        assertEq(usdcBase.balanceOf(address(almProxy)),  0);
        assertEq(usdcBase.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(foreignController.withdrawAave(ATOKEN_USDC, type(uint256).max), fullBalance);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);  // No change

        assertEq(ausdc.balanceOf(address(almProxy)),    0);
        assertEq(usdcBase.balanceOf(address(almProxy)), fullBalance);
        assertEq(usdcBase.balanceOf(address(ausdc)),    startingAUSDCBalance + 1_000_000e6 - fullBalance);
    }

}
