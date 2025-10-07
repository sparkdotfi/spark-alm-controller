// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IPendleMarket, ISY } from "../../src/interfaces/PendleInterfaces.sol";

import "./ForkTestBase.t.sol";

contract PendleTestBase is ForkTestBase {

    // sUSDe 25 Sep 2025 market
    IPendleMarket pendleMarket = IPendleMarket(0xA36b60A14A1A5247912584768C6e53E1a269a9F7);

    address PT_WHALE = 0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364;

    bytes32 redeemKey;

    function setUp() public virtual override {
        super.setUp();

        redeemKey = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.startPrank(GROVE_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23319550;  // 8 Sep 2025
    }

}

contract MainnetControllerRedeemFailurePendleTests is PendleTestBase {

    function test_redeemPendlePT_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_marketNotExpired() public {
        vm.warp(pendleMarket.expiry() - 1);

        vm.prank(relayer);
        vm.expectRevert("PendleLib/market-not-expired");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_zeroMaxAmount() public {
        vm.prank(GROVE_PROXY);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_rateLimitsBoundary() public {
        vm.prank(GROVE_PROXY);
        rateLimits.setRateLimitData(redeemKey, 500_000e18, 1);

        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18 + 1, 1);
    }

    function test_redeemPendlePT_insufficientBalance() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18 + 1, 1);
    }

    function test_redeemPendlePT_amountTooSmall() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        mainnetController.redeemPendlePT(address(pendleMarket), 5, 1);
    }

    function test_redeemPendlePT_minAmountOutNotSet() public {
        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("PendleLib/min-amount-out-not-set");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, 0);
    }

    function test_redeemPendlePT_minAmountOutNotMet() public {
        (address sy, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 exchangeRate = ISY(sy).exchangeRate();
        uint256 exactAmountOut = 1_000_000e18 * 1e18 / exchangeRate; // Exact at this particular point in time

        vm.prank(relayer);
        vm.expectRevert("PendleLib/min-amount-not-met");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, exactAmountOut + 1);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, exactAmountOut);

    }

}

contract MainnetControllerRedeemSuccessPendleTests is PendleTestBase {

    function test_redeemPendlePT_sUSDe() public {
        // Default Pendle market used in tests is already a sUSDe market

        address ptDonor = PT_WHALE;

        (address sy, address pt,) = pendleMarket.readTokens();
        IERC20 yieldToken = IERC20(ISY(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);
        vm.stopPrank();

        assertEq(IERC20(pt).balanceOf(address(almProxy)),         1_000_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 0);

        vm.warp(pendleMarket.expiry());

        uint256 exchangeRate   = ISY(sy).exchangeRate();
        uint256 exactAmountOut = 500_000e18 * 1e18 / exchangeRate;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 500_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 500_000e18 * 1e18 / exchangeRate);

        vm.warp(block.timestamp + 14 days);

        exchangeRate   = ISY(sy).exchangeRate();
        exactAmountOut = 500_000e18 * 1e18 / exchangeRate;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 0);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 1_000_000e18 * 1e18 / exchangeRate);
    }

    function test_redeemPendlePT_USDe() public {
        pendleMarket = IPendleMarket(0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4);
        redeemKey = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.prank(GROVE_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        address ptDonor = 0x925109e0AfFe306c31B55d8181e766D53aF7A778;

        (address sy, address pt,) = pendleMarket.readTokens();
        IERC20 yieldToken = IERC20(ISY(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20(pt).transfer((address(almProxy)), 1_000_000e18);
        vm.stopPrank();

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 0);

        vm.warp(pendleMarket.expiry());
        uint256 exchangeRate   = ISY(sy).exchangeRate();
        uint256 exactAmountOut = 500_000e18 * 1e18 / exchangeRate;
        assertEq(exchangeRate, 1e18);

        assertEq(exactAmountOut, 500_000e18);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 500_000e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 500_000e18);

        vm.warp(block.timestamp + 18 days);

        exchangeRate = ISY(sy).exchangeRate();
        assertEq(exchangeRate, 1e18);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 0);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 1_000_000e18);
    }

    function test_redeemPendlePT_stETH() public {
        pendleMarket = IPendleMarket(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2);
        redeemKey = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.prank(GROVE_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10e18, uint256(10e18) / 1 days);

        address ptDonor = 0x2B67d059e41a65C58b02EE1FA99DADa70c55358F;

        (address sy, address pt,) = pendleMarket.readTokens();
        IERC20 yieldToken = IERC20(ISY(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20(pt).transfer((address(almProxy)), 10e18);
        vm.stopPrank();

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 10e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 0);

        vm.warp(pendleMarket.expiry());
        uint256 exchangeRate   = ISY(sy).exchangeRate();
        uint256 exactAmountOut = 5e18 * 1e18 / exchangeRate;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 5e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 5e18);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 5e18 * 1e18 / exchangeRate);

        vm.warp(block.timestamp + 14 days);
        exchangeRate   = ISY(sy).exchangeRate();
        exactAmountOut = 5e18 * 1e18 / exchangeRate;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 5e18, exactAmountOut);

        assertEq(IERC20(pt).balanceOf(address(almProxy)), 0);
        assertEq(IERC20(yieldToken).balanceOf(address(almProxy)), 10e18 * 1e18 / exchangeRate);
    }

}
