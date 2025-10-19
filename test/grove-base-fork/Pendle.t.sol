// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IPendleMarket, ISY, IYT } from "../../src/interfaces/PendleInterfaces.sol";

import "./ForkTestBase.t.sol";

contract PendleTestBase is ForkTestBase {

    // USDe 11 Dec 2025 market
    IPendleMarket pendleMarket = IPendleMarket(0x8991847176b1D187e403dd92a4E55fC8d7684538);

    address PT_WHALE = 0x26b6B3e01fB0ba398e25b1ADbE295036A32E696c;

    bytes32 redeemKey;

    function setUp() public virtual override {
        super.setUp();

        redeemKey = RateLimitHelpers.makeAssetKey(
            foreignController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);
        vm.stopPrank();
    }

}

contract ForeignControllerRedeemFailurePendleTests is PendleTestBase {

    function test_redeemPendlePT_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_marketNotExpired() public {
        vm.warp(pendleMarket.expiry() - 1);

        vm.prank(ALM_RELAYER);
        vm.expectRevert("PendleLib/market-not-expired");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_zeroMaxAmount() public {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(ALM_RELAYER);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_rateLimitsBoundary() public {
        (, address pt, address yt) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYT(yt).pyIndexCurrent();
        uint256 exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, exactAmountOut - 1, 1);

        vm.prank(ALM_RELAYER);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_insufficientBalance() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(ALM_RELAYER);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18 + 1, 1);
    }

    function test_redeemPendlePT_amountTooSmall() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(ALM_RELAYER);
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        foreignController.redeemPendlePT(address(pendleMarket), 4, 1);
    }

    function test_redeemPendlePT_minAmountOutNotSet() public {
        vm.warp(pendleMarket.expiry());

        vm.prank(ALM_RELAYER);
        vm.expectRevert("PendleLib/min-amount-out-not-set");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, 0);
    }

    function test_redeemPendlePT_minAmountOutNotMet() public {
        (, address pt, address yt) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYT(yt).pyIndexCurrent();
        uint256 exactAmountOut = 100_000e18 * 1e18 / pyIndexCurrent; // Exact at this particular point in time

        vm.prank(ALM_RELAYER);
        vm.expectRevert("PendleLib/min-amount-not-met");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, exactAmountOut + 1);

        vm.prank(ALM_RELAYER);
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, exactAmountOut);

    }

}

contract ForeignControllerRedeemSuccessPendleTests is PendleTestBase {

    function test_redeemPendlePT() public {
        // Default Pendle market used in tests is already a sUSDe market

        address ptDonor = PT_WHALE;

        (address sy, address pt, address yt) = pendleMarket.readTokens();
        IERC20 yieldToken = IERC20(ISY(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20(pt).transfer((address(almProxy)), 100_000e18);
        vm.stopPrank();

        assertEq(IERC20(pt).balanceOf(address(almProxy)),         100_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 0);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYT(yt).pyIndexCurrent();
        uint256 exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(ALM_RELAYER);
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 50_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 50_000e18 * 1e18 / pyIndexCurrent);

        vm.warp(block.timestamp + 14 days);

        pyIndexCurrent = IYT(yt).pyIndexCurrent();
        exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(ALM_RELAYER);
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 0);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 100_000e18 * 1e18 / pyIndexCurrent);
    }

}
