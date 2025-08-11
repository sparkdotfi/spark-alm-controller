// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import "./ForkTestBase.t.sol";

contract AaveV3MainMarketBaseTest is ForkTestBase {

    address constant ATOKEN_USDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant POOL        = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    IAToken ausds = IAToken(ATOKEN_USDS);
    IAToken ausdc = IAToken(ATOKEN_USDC);

    uint256 startingAUSDSBalance;
    uint256 startingAUSDCBalance;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.GROVE_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDS
            ),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDC
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDS
            ),
            10_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        vm.stopPrank();

        startingAUSDCBalance = usdc.balanceOf(address(ausdc));
        startingAUSDSBalance = usds.balanceOf(address(ausds));
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used

contract AaveV3MainMarketDepositFailureTests is AaveV3MainMarketBaseTest {

    function test_depositAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositAave(makeAddr("fake-token"), 1e18);
    }

    function test_depositAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18 + 1);

        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18);
    }

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6 + 1);

        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6);
    }

}

contract AaveV3MainMarketDepositSuccessTests is AaveV3MainMarketBaseTest {

    function test_depositAave_usds() public {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  1_000_000e18);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(ausds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);
    }

    function test_depositAave_usdc() public {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);
    }

}

contract AaveV3MainMarketWithdrawFailureTests is AaveV3MainMarketBaseTest {

    function test_withdrawAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.withdrawAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_withdrawAave_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            0,
            0
        );
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_withdrawAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 15_000_000e18);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDS, 15_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18 + 1);

        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18);
    }

    function test_withdrawAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 15_000_000e6);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDC, 15_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6 + 1);

        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6);
    }

}

contract AaveV3MainMarketWithdrawSuccessTests is AaveV3MainMarketBaseTest {

    function test_withdrawAave_usds() public {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDS
        );

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 days);

        uint256 fullBalance = ausds.balanceOf(address(almProxy));

        assertGe(fullBalance, 1_000_000e18);

        assertEq(ausds.balanceOf(address(almProxy)), fullBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, 400_000e18), 400_000e18);

        assertEq(ausds.balanceOf(address(almProxy)), fullBalance - 400_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  400_000e18);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 600_000e18);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(key), 9_600_000e18);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), fullBalance - 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18 - fullBalance);

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  fullBalance);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18 - fullBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLe(usds.balanceOf(address(ausds)), startingAUSDSBalance);
    }

    function test_withdrawAave_usds_unlimitedRateLimit() public {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDS
        );
        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setUnlimitedRateLimitData(key);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 days);

        uint256 fullBalance = ausds.balanceOf(address(almProxy));

        assertGe(fullBalance, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);

        assertEq(ausds.balanceOf(address(almProxy)), fullBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), fullBalance);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);  // No change

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  fullBalance);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18 - fullBalance);
    }

    function test_withdrawAave_usdc() public {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 days);

        uint256 fullBalance = ausdc.balanceOf(address(almProxy));

        assertGe(fullBalance, 1_000_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)), fullBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)), fullBalance - 400_000e6 + 1);  // Rounding
        assertEq(usdc.balanceOf(address(almProxy)),  400_000e6);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 600_000e6);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(key), 9_600_000e6);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), fullBalance - 400_000e6 + 1);  // Rounding

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  fullBalance + 1);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6 - fullBalance - 1);  // Rounding

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6 - fullBalance - 1);  // Rounding

        // Interest accrued was withdrawn, reducing cash balance
        assertLe(usdc.balanceOf(address(ausdc)), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() public {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );
        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setUnlimitedRateLimitData(key);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 days);

        uint256 fullBalance = ausdc.balanceOf(address(almProxy));

        assertGe(fullBalance, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);

        assertEq(ausdc.balanceOf(address(almProxy)), fullBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), fullBalance);

        assertEq(rateLimits.getCurrentRateLimit(key), type(uint256).max);  // No change

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  fullBalance);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6 - fullBalance);
    }

}
