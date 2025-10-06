// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock }      from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }      from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { OTC } from "src/MainnetController.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import "./ForkTestBase.t.sol";

// Mock ERC20 with variable decimals
contract ERC20 is ERC20Mock {

    uint8 immutable internal _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

}

contract MainnetControllerOTCSwapBase is ForkTestBase {

    bytes32 LIMIT_OTC_SWAP = keccak256("LIMIT_OTC_SWAP");

    bytes32 key;

    OTCBuffer otcBuffer;

    event OTCBufferSet(
        address indexed exchange,
        address indexed newOTCBuffer,
        address indexed oldOTCBuffer
    );
    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256 amountSent,
        uint256 amountSent18
    );
    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed assetClaimed,
        uint256 amountClaimed,
        uint256 amountClaimed18
    );
    event OTCRechargeRateSet(address indexed exchange, uint256 oldRate18, uint256 newRate18);

    address exchange = makeAddr("exchange");

    function setUp() public virtual override {
        super.setUp();

        otcBuffer = new OTCBuffer(Ethereum.SPARK_PROXY);

        vm.startPrank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(usdt), address(almProxy), type(uint256).max);
        otcBuffer.approve(address(usds), address(almProxy), type(uint256).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            LIMIT_OTC_SWAP,
            exchange
        );

        vm.startPrank(Ethereum.SPARK_PROXY);

        // NOTE: This is asset agnostic but USD based
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        mainnetController.setMaxSlippage(exchange, 0.95e18);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        vm.stopPrank();
    }
}

contract MainnetControllerotcSendFailureTests is MainnetControllerOTCSwapBase {

    function test_otcSend_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcSend(exchange, address(1), 1e18);
    }

    function test_otcSend_assetToSendZero() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/asset-to-send-zero");
        mainnetController.otcSend(exchange, address(0), 1e18);
    }

    function test_otcSend_amountToSendZero() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/amount-to-send-zero");
        mainnetController.otcSend(exchange, address(usdt), 0);
    }

    function otcSend_rateLimitZero() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.otcSend(makeAddr("fake-exchange"), address(usdt), 1e18);
    }

    function test_otcSend_usdt_rateLimitedBoundary() external {
        deal(address(usdt), address(almProxy), 10_000_000e6 + 1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6 + 1);

        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);
    }

    function test_otcSend_usds_rateLimitedBoundary() external {
        deal(address(usds), address(almProxy), 10_000_000e18 + 1);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18 + 1);

        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);
    }

    function test_otcSend_otcBufferNotSet() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(0));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usdt() external {
        deal(address(usdt), address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 5_000_000e6);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        ( address buffer,,,, ) = mainnetController.otcs(exchange);

        // 5m * 95% slippage = 4.75m
        deal(address(usdt), buffer, 4_750_000e6 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18 - 1e12);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        deal(address(usdt), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usds() external {
        deal(address(usds), address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 5_000_000e18);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        ( address buffer,,,, ) = mainnetController.otcs(exchange);

        // 5m * 95% slippage = 4.75m
        deal(address(usds), buffer, 4_750_000e18 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18 - 1);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usds), 1e18);

        deal(address(usds), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usdt() external {
        deal(address(usdt), address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 5_000_000e6);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        ( address buffer,,,, ) = mainnetController.otcs(exchange);

        // 5m * 95% slippage = 4.75m
        deal(address(usdt), buffer, 4_750_000e6 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18 - 1e12);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        skip(1 seconds);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usds() external {
        deal(address(usds), address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 5_000_000e18);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        ( address buffer,,,, ) = mainnetController.otcs(exchange);

        // 5m * 95% slippage = 4.75m
        deal(address(usds), buffer, 4_750_000e18 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18 - 1);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usds), 1e18);

        skip(1 seconds);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 4_750_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

}

contract MainnetControllerotcSendSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSend_usdt() external {
        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
            = mainnetController.otcs(exchange);

        assertEq(swapTimestamp, 0);
        assertEq(sent18,        0);
        assertEq(claimed18,     0);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(exchange)), 10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_otcSend_usds() external {
        // Mint tokens
        deal(address(usds), address(almProxy), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
            = mainnetController.otcs(exchange);

        assertEq(swapTimestamp, 0);
        assertEq(sent18,        0);
        assertEq(claimed18,     0);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

        ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(exchange)), 10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

// contract MainnetControllerOTCClaimFailureTests is MainnetControllerOTCSwapBase {

//     function test_otcClaim_notRelayer() external {
//         vm.expectRevert(abi.encodeWithSignature(
//             "AccessControlUnauthorizedAccount(address,bytes32)",
//             address(this),
//             RELAYER
//         ));
//         mainnetController.otcClaim(exchange, address(1));
//     }

//     function test_otcClaim_assetToClaimZero() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCBuffer(exchange, address(otcBuffer));

//         vm.prank(relayer);
//         vm.expectRevert("MainnetController/asset-to-claim-zero");
//         mainnetController.otcClaim(exchange, address(0));
//     }

//     function test_otcClaim_otcBufferNotSet() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCBuffer(exchange, address(0));

//         vm.prank(relayer);
//         vm.expectRevert("MainnetController/otc-buffer-not-set");
//         mainnetController.otcClaim(exchange, address(1));
//     }

// }

// contract MainnetControllerOTCClaimSuccessTests is MainnetControllerOTCSwapBase {

//     function test_e2e_swapUsdtToUsds() external {
//         uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));
//         uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));

//         // Mint tokens
//         deal(address(usdt), address(almProxy), 10_000_000e6);
//         deal(address(usds), address(exchange), 9_500_000e18);

//         assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 10_000_000e6);
//         assertEq(usds.balanceOf(address(otcBuffer)), 0);

//         assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

//         assertEq(usdt.balanceOf(address(almProxy)), usdtBalanceALMProxy);

//         assertEq(rateLimits.getCurrentRateLimit(key), 0);

//         vm.prank(exchange);
//         SafeERC20.safeTransfer(IERC20Metadata(address(usds)), address(otcBuffer), 9_500_000e18);

//         assertEq(usds.balanceOf(address(otcBuffer)), 9_500_000e18);

//         ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
//             = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, uint48(block.timestamp));
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     0);

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);
//         assertEq(usds.balanceOf(address(otcBuffer)), 9_500_000e18);

//         skip(1 days);

//         // Claim
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCClaimed(exchange, address(otcBuffer), address(usds), 9_500_000e18, 9_500_000e18);
//         mainnetController.otcClaim(exchange, address(usds));

//         ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, block.timestamp - 1 days);
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     9_500_000e18);

//         assertEq(usds.balanceOf(address(almProxy)),  9_500_000e18);
//         assertEq(usds.balanceOf(address(otcBuffer)), 0);
//     }

//     function test_e2e_swapUsdtToUsds_withRecharge() external {
//         uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));
//         uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));

//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         // Mint tokens
//         deal(address(usdt), address(almProxy), 10_000_000e6);
//         deal(address(usds), address(exchange), 8_500_000e18);

//         assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 10_000_000e6);
//         assertEq(usds.balanceOf(address(otcBuffer)), 0);

//         assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

//         assertEq(usdt.balanceOf(address(almProxy)), usdtBalanceALMProxy);

//         assertEq(rateLimits.getCurrentRateLimit(key), 0);

//         vm.prank(exchange);
//         SafeERC20.safeTransfer(IERC20Metadata(address(usds)), address(otcBuffer), 8_500_000e18);

//         assertEq(usds.balanceOf(address(otcBuffer)), 8_500_000e18);

//         ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
//             = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, uint48(block.timestamp));
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     0);

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);
//         assertEq(usds.balanceOf(address(otcBuffer)), 8_500_000e18);

//         skip(1 days);

//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         // Claim
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCClaimed(exchange, address(otcBuffer), address(usds), 8_500_000e18, 8_500_000e18);
//         mainnetController.otcClaim(exchange, address(usds));

//         ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, block.timestamp - 1 days);
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     8_500_000e18);

//         // Still not ready
//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         skip(1 seconds);

//         // Now it is ready
//         assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 8_500_000e18);
//         assertEq(usds.balanceOf(address(otcBuffer)), 0);
//     }

//     function test_e2e_swapUsdsToUsdt() external {
//         uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));
//         uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));

//         // Mint tokens
//         deal(address(usds), address(almProxy), 10_000_000e18);
//         deal(address(usdt), address(exchange), 9_500_000e6);

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 10_000_000e18);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 0);

//         assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
//         mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

//         assertEq(usds.balanceOf(address(almProxy)), usdsBalanceALMProxy);

//         assertEq(rateLimits.getCurrentRateLimit(key), 0);

//         vm.prank(exchange);
//         SafeERC20.safeTransfer(IERC20Metadata(address(usdt)), address(otcBuffer), 9_500_000e6);

//         assertEq(usdt.balanceOf(address(otcBuffer)), 9_500_000e6);

//         ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
//             = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, uint48(block.timestamp));
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     0);

//         assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 9_500_000e6);

//         skip(1 days);

//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         // Claim
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCClaimed(exchange, address(otcBuffer), address(usdt), 9_500_000e6, 9_500_000e18);
//         mainnetController.otcClaim(exchange, address(usdt));

//         ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, block.timestamp - 1 days);
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     9_500_000e18);

//         assertEq(usdt.balanceOf(address(almProxy)),  9_500_000e6);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 0);

//         assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
//     }

//     function test_e2e_swapUsdsToUsdt_withRecharge() external {
//         uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));
//         uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));

//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         // Mint tokens
//         deal(address(usds), address(almProxy), 10_000_000e18);
//         deal(address(usdt), address(exchange), 8_500_000e6);

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 10_000_000e18);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 0);

//         assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
//         mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

//         assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);

//         assertEq(rateLimits.getCurrentRateLimit(key), 0);

//         vm.prank(exchange);
//         SafeERC20.safeTransfer(IERC20Metadata(address(usdt)), address(otcBuffer), 8_500_000e6);

//         assertEq(usdt.balanceOf(address(otcBuffer)), 8_500_000e6);

//         ( ,, uint256 swapTimestamp, uint256 sent18, uint256 claimed18 )
//             = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, uint48(block.timestamp));
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     0);

//         assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 8_500_000e6);

//         skip(1 days);

//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         // Claim
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCClaimed(exchange, address(otcBuffer), address(usdt), 8_500_000e6, 8_500_000e18);
//         mainnetController.otcClaim(exchange, address(usdt), 8_500_000e6);

//         ( ,, swapTimestamp, sent18, claimed18 ) = mainnetController.otcs(exchange);

//         assertEq(swapTimestamp, block.timestamp - 1 days);
//         assertEq(sent18,        10_000_000e18);
//         assertEq(claimed18,     8_500_000e18);

//         // Still not ready
//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         skip(1 seconds);

//         // Now it is ready
//         assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

//         assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 8_500_000e6);
//         assertEq(usdt.balanceOf(address(otcBuffer)), 0);
//     }

// }

// contract MainnetControlergetOtcClaimedWithRechargeTests is MainnetControllerOTCSwapBase {

//     function test_getOtcClaimedWithRecharge() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         // Mint tokens
//         deal(address(usdt), address(almProxy), 10_000_000e6);
//         deal(address(usds), address(exchange), 5_500_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(
//             exchange,
//             address(usdt),
//             10_000_000e6
//         );

//         vm.prank(exchange);
//         usds.transfer(address(otcBuffer), 5_500_000e18);

//         // Claim
//         vm.prank(relayer);
//         mainnetController.otcClaim(exchange, address(usds));

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18);

//         skip(1 days);
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 6_499_999.999999999999993600e18);

//         skip(1 days);
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 7_499_999.999999999999987200e18);

//         skip(2 days);
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 9_499_999.999999999999974400e18);

//         skip(1 days);
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 10_499999.999999999999968000e18);

//         skip(10 days);
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 20_499_999.999999999999904000e18);
//     }

// }

// contract MainnetControllerIsOTCSwapReadySuccessTests is MainnetControllerOTCSwapBase {

//     function test_isOtcSwapReady_falseWithZeroSlippage() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setMaxSlippage(exchange, 0);

//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
//     }

//     function test_isOtcSwapReady() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         // Mint tokens
//         deal(address(usdt), address(almProxy), 10_000_000e6);
//         deal(address(usds), address(exchange), 5_500_000e18);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(
//             exchange,
//             address(usdt),
//             10_000_000e6
//         );

//         vm.prank(exchange);
//         usds.transfer(address(otcBuffer), 5_500_000e18);

//         // Claim
//         vm.prank(relayer);
//         mainnetController.otcClaim(exchange, address(usds), 5_500_000e18);

//         // Skip time by 4 days to recharge
//         skip(4 days);
//         assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

//         skip(1 seconds);
//         assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
//     }

// }

