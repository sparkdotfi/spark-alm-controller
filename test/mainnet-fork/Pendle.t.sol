// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum as SparkEthereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { Ethereum as GroveEthereum } from "../../lib/grove-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256 balance);

}

interface IPendleMarketLike {

    function expiry() external view returns (uint256);

    function readTokens() external view returns (address sy, address pt, address yt);

}

interface ISYLike {

    function yieldToken() external view returns (address);

}

interface IYTLike {

    function pyIndexCurrent() external returns (uint256);

}

contract PendleTestBase is ForkTestBase {

    // sUSDe 25 Sep 2025 market
    IPendleMarketLike pendleMarket = IPendleMarketLike(0xA36b60A14A1A5247912584768C6e53E1a269a9F7);

    address PT_WHALE = 0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364;

    bytes32 redeemKey;

    function setUp() public virtual override {
        super.setUp();

        redeemKey = makeAddressKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.prank(SparkEthereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);
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
            RELAYER_ROLE
        ));
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_marketNotExpired() public {
        vm.warp(pendleMarket.expiry() - 1);

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/market-not-expired");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_zeroMaxAmount() public {
        vm.prank(SparkEthereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_rateLimitsBoundary() public {
        (, address pt, address yt) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 500_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(SparkEthereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, exactAmountOut - 1, 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, 1);
    }

    function test_redeemPendlePT_insufficientBalance() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18 + 1, 1);
    }

    function test_redeemPendlePT_amountTooSmall() public {
        (, address pt,) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        mainnetController.redeemPendlePT(address(pendleMarket), 5, 1);
    }

    function test_redeemPendlePT_minAmountOutNotSet() public {
        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/min-amount-out-not-set");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, 0);
    }

    function test_redeemPendlePT_minAmountOutNotMet() public {
        (, address pt, address yt) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 1_000_000e18 * 1e18 / pyIndexCurrent; // Exact at this particular point in time

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/min-amount-not-met");
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, exactAmountOut + 1);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 1_000_000e18, exactAmountOut);

    }

}

contract MainnetControllerRedeemSuccessPendleTests is PendleTestBase {

    function test_redeemPendlePT_sUSDe() public {
        // Default Pendle market used in tests is already a sUSDe market

        address ptDonor = PT_WHALE;

        (address sy, address pt, address yt) = pendleMarket.readTokens();
        IERC20Like yieldToken = IERC20Like(ISYLike(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);
        vm.stopPrank();

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     0);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 500_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 500_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     500_000e18 * 1e18 / pyIndexCurrent);

        vm.warp(block.timestamp + 14 days);

        pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        exactAmountOut = 500_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 0);
        assertEq(yieldToken.balanceOf(address(almProxy)),     1_000_000e18 * 1e18 / pyIndexCurrent);
    }

    function test_redeemPendlePT_USDe() public {
        pendleMarket = IPendleMarketLike(0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4);
        redeemKey = makeAddressKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.prank(SparkEthereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        address ptDonor = 0x925109e0AfFe306c31B55d8181e766D53aF7A778;

        (address sy, address pt, address yt) = pendleMarket.readTokens();
        IERC20Like yieldToken = IERC20Like(ISYLike(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20Like(pt).transfer((address(almProxy)), 1_000_000e18);
        vm.stopPrank();

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     0);

        vm.warp(pendleMarket.expiry());
        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 500_000e18 * 1e18 / pyIndexCurrent;
        assertEq(pyIndexCurrent, 1e18);

        assertEq(exactAmountOut, 500_000e18);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 500_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     500_000e18);

        vm.warp(block.timestamp + 18 days);

        pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        assertEq(pyIndexCurrent, 1e18);

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 500_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 0);
        assertEq(yieldToken.balanceOf(address(almProxy)),     1_000_000e18);
    }

    function test_redeemPendlePT_stETH() public {
        pendleMarket = IPendleMarketLike(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2);
        redeemKey = makeAddressKey(
            mainnetController.LIMIT_PENDLE_PT_REDEEM(),
            address(pendleMarket)
        );

        vm.prank(SparkEthereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 10e18, uint256(10e18) / 1 days);

        address ptDonor = 0x2B67d059e41a65C58b02EE1FA99DADa70c55358F;

        (address sy, address pt, address yt) = pendleMarket.readTokens();
        IERC20Like yieldToken = IERC20Like(ISYLike(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20Like(pt).transfer((address(almProxy)), 10e18);
        vm.stopPrank();

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 10e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     0);

        vm.warp(pendleMarket.expiry());
        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 5e18 * 1e18 / pyIndexCurrent;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 5e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 5e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     5e18 * 1e18 / pyIndexCurrent);

        vm.warp(block.timestamp + 14 days);
        pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        exactAmountOut = 5e18 * 1e18 / pyIndexCurrent;

        vm.prank(relayer);
        mainnetController.redeemPendlePT(address(pendleMarket), 5e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 0);
        assertEq(yieldToken.balanceOf(address(almProxy)),     10e18 * 1e18 / pyIndexCurrent);
    }

}
