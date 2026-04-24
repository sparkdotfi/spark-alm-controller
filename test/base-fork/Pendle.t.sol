// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base as SparkBase } from "../../lib/spark-address-registry/src/Base.sol";
import { Base as GroveBase } from "../../lib/grove-address-registry/src/Base.sol";

import { makeAddressAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { IPendleFacet } from "../../src/facets/pendle/IPendleFacet.sol";

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

abstract contract Pendle_TestBase is ForkTestBase {

    // USDe 11 Dec 2025 market
    IPendleMarketLike pendleMarket = IPendleMarketLike(0x8991847176b1D187e403dd92a4E55fC8d7684538);

    address PT_WHALE = 0x26b6B3e01fB0ba398e25b1ADbE295036A32E696c;

    bytes32 redeemKey;

    function setUp() public virtual override {
        super.setUp();

        ( , address pt, ) = pendleMarket.readTokens();

        redeemKey = makeAddressAddressKey(
            foreignController.LIMIT_PENDLE_PT_REDEEM(),
            pt,
            address(pendleMarket)
        );

        vm.prank(SparkBase.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 37_589_683;
    }

}

contract ForeignController_Pendle_Redeem_FailureTests is Pendle_TestBase {

    function test_redeemPendlePT_notRelayer() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_marketNotExpired() public {
        vm.warp(pendleMarket.expiry() - 1);

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/market-not-expired");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_zeroMaxAmount() public {
        vm.prank(SparkBase.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        ( , address pt, ) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_rateLimitsBoundary() public {
        ( , address pt, address yt ) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.prank(SparkBase.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(redeemKey, exactAmountOut - 1, 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, 1);
    }

    function test_redeemPendlePT_insufficientBalance() public {
        ( , address pt, ) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18 + 1, 1);
    }

    function test_redeemPendlePT_amountTooSmall() public {
        ( , address pt, ) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)");
        foreignController.redeemPendlePT(address(pendleMarket), 4, 1);
    }

    function test_redeemPendlePT_minAmountOutNotSet() public {
        vm.warp(pendleMarket.expiry());

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/min-amount-out-not-set");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, 0);
    }

    function test_redeemPendlePT_minAmountOutNotMet() public {
        ( , address pt, address yt ) = pendleMarket.readTokens();
        vm.prank(PT_WHALE);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 100_000e18 * 1e18 / pyIndexCurrent; // Exact at this particular point in time

        vm.prank(relayer);
        vm.expectRevert("PendleFacet/min-amount-not-met");
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, exactAmountOut + 1);

        vm.prank(relayer);
        foreignController.redeemPendlePT(address(pendleMarket), 100_000e18, exactAmountOut);

    }

}

contract ForeignController_Pendle_Redeem_SuccessTests is Pendle_TestBase {

    function test_redeemPendlePT() public {
        // Default Pendle market used in tests is already a sUSDe market

        address ptDonor = PT_WHALE;

        ( address sy, address pt, address yt ) = pendleMarket.readTokens();
        IERC20Like yieldToken = IERC20Like(ISYLike(sy).yieldToken());

        vm.startPrank(ptDonor);
        IERC20Like(pt).transfer((address(almProxy)), 100_000e18);
        vm.stopPrank();

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 100_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     0);

        vm.warp(pendleMarket.expiry());

        uint256 pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        uint256 exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.expectEmit(address(foreignController));
        emit IPendleFacet.PendleRedeem(address(pendleMarket), 50_000e18, exactAmountOut);

        vm.prank(relayer);
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 50_000e18);
        assertEq(yieldToken.balanceOf(address(almProxy)),     50_000e18 * 1e18 / pyIndexCurrent);

        vm.warp(block.timestamp + 14 days);

        pyIndexCurrent = IYTLike(yt).pyIndexCurrent();
        exactAmountOut = 50_000e18 * 1e18 / pyIndexCurrent;

        vm.expectEmit(address(foreignController));
        emit IPendleFacet.PendleRedeem(address(pendleMarket), 50_000e18, exactAmountOut);

        vm.prank(relayer);
        foreignController.redeemPendlePT(address(pendleMarket), 50_000e18, exactAmountOut);

        assertEq(IERC20Like(pt).balanceOf(address(almProxy)), 0);
        assertEq(yieldToken.balanceOf(address(almProxy)),     100_000e18 * 1e18 / pyIndexCurrent);
    }

}
