// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC20Mock }       from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IOTCFacet } from "../../src/facets/otc/IOTCFacet.sol";
import { OTCFacet }  from "../../src/facets/otc/OTCFacet.sol";

import { OTCBuffer } from "../../src/facets/otc/OTCBuffer.sol";

import { MockTokenReturnFalse, MockTokenReturn64Bytes } from "../mocks/Mocks.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    // Purposely not returning bool to avoid reverts on transfers.
    function transfer(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

}

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

abstract contract OTC_TestBase is ForkTestBase {

    IERC20Like internal constant USDT = IERC20Like(Ethereum.USDT);
    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    OTCBuffer internal otcBuffer;

    address internal exchange = makeAddr("exchange");

    function setUp() public virtual override {
        super.setUp();

        otcBuffer = OTCBuffer(
            address(
                new ERC1967Proxy(
                    address(new OTCBuffer()),
                    abi.encodeCall(
                        OTCBuffer.initialize,
                        (Ethereum.SPARK_PROXY, address(almProxy))
                    )
                )
            )
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(Ethereum.USDT, type(uint256).max);
        otcBuffer.approve(Ethereum.USDS, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(Ethereum.SPARK_PROXY);

        mainnetController.otc_setMaxSlippage(exchange, 0.9995e18);
        mainnetController.otc_setRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        vm.stopPrank();
    }

    function _assertOTCState(uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed)
        internal
        view
    {
        (
            uint256 normalizedSent_,
            uint256 sentTimestamp_,
            uint256 normalizedClaimed_
        ) = mainnetController.otc_getState(exchange);

        assertEq(normalizedSent_,    normalizedSent);
        assertEq(sentTimestamp_,     sentTimestamp);
        assertEq(normalizedClaimed_, normalizedClaimed);
    }

}

// NOTE: This test requires the send to be executed first which requires `ForkTestBase`, therefore
//       it is placed here instead of in the `OTCFacet` integrations tests for the setters.
contract MainnetController_OTC_SetOTCBuffer_Tests is OTC_TestBase {

    function test_setOTCBuffer_swapInProgress() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDT), 5_000_000e6, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        vm.expectRevert("OTCFacet/swap-in-progress");
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, makeAddr("new-buffer"));
    }

    function test_setOTCBuffer_afterSwapReady() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT), 10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 5_000_000e6);

        // Execute and fully settle a swap so the exchange is ready for buffer rotation.
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        // 5m * 99.95% slippage = 4.9975m returned meets the readiness threshold exactly.
        deal(Ethereum.USDT, address(otcBuffer), 4_997_500e6);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        ( , uint256 sentTimestamp, ) = mainnetController.otc_getState(exchange);

        assertEq(sentTimestamp,                                  block.timestamp);
        assertEq(mainnetController.otc_getIsSwapReady(exchange), true);

        // sentTimestamp != 0 but the swap is ready, so setBuffer takes the getIsSwapReady branch
        // of the require and rotates the buffer instead of reverting "swap-in-progress".
        address newBuffer = makeAddr("new-buffer");

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCBufferSet(exchange, newBuffer);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, newBuffer);

        assertEq(mainnetController.otc_getBuffer(exchange), newBuffer);
    }

}

contract MainnetController_OTC_Send_Tests is OTC_TestBase {

    function test_otcSend_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.otc_send(exchange, address(1), 1e18);
    }

    function test_otcSend_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.otc_send(exchange, address(1), 1e18);
    }

    function test_otcSend_assetToSendZero() external {
        vm.expectRevert("OTCFacet/asset-zero-address");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, address(0), 1e18);
    }

    function test_otcSend_amountToSendZero() external {
        vm.expectRevert("OTCFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 0);
    }

    function test_otcSend_bufferNotSet() external {
        vm.expectRevert("OTCFacet/buffer-not-set");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, address(1), 1e18);
    }

    function test_otcSend_rateLimitZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e18);
    }

    function test_otcSend_usdt_rateLimitedBoundary() external {
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6 + 1);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDT), 10_000_000e6, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);
    }

    function test_otcSend_usds_rateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 10_000_000e18 + 1);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDS), 10_000_000e18, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 10_000_000e18 + 1);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 10_000_000e18);
    }

    function test_otcSend_transferFailed() external {
        address token = address(new MockTokenReturnFalse());

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, token), 1_000_000e6, 0);
        vm.stopPrank();

        deal(token, address(almProxy), 1_000_000e6);

        vm.expectRevert("OTCFacet/transfer-failed");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, token, 1_000_000e6);
    }

    function test_otcSend_transferFailedOnNonStandardReturnData() external {
        address token = address(new MockTokenReturn64Bytes());

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, token), 1_000_000e6, 0);
        vm.stopPrank();

        vm.expectRevert("OTCFacet/transfer-failed");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, token, 1_000_000e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usdt() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT), 10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        // 5m * 99.95% slippage = 4.9975m
        deal(Ethereum.USDT, address(otcBuffer), 4_997_500e6 - 1);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        // Six decimal asset conversion
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e6);

        deal(Ethereum.USDT, address(otcBuffer), 1);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usds() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDS), 10_000_000e18,     0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 5_000_000e18);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        // 5m * 99.95% slippage = 4.9975m
        deal(Ethereum.USDS, address(otcBuffer), 4_997_500e18 - 1);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 1e18);

        deal(Ethereum.USDS, address(otcBuffer), 1);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 1e18);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usdt() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT), 10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        // 5m * 99.95% slippage = 4.9975m
        deal(Ethereum.USDT, address(otcBuffer), 4_997_500e6 - 1);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        // Six decimal asset conversion
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e6);

        skip(1 seconds);

        assertGt(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usds() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDS), 10_000_000e18,     0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 5_000_000e18);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        // 5m * 99.95% slippage = 4.9975m
        deal(Ethereum.USDS, address(otcBuffer), 4_997_500e18 - 1);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        // Six decimal asset conversion
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 1e18);

        skip(1 seconds);

        assertGt(mainnetController.otc_getClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 1e18);
    }

    // NOTE: This test covers the case where token returns null for transfer
    function test_otcSend_usdt() external {
        bytes32 sendRateLimitKey = mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDT);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(sendRateLimitKey, 10_000_000e6, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        assertEq(USDT.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(USDT.balanceOf(exchange),          0);

        assertEq(rateLimits.getCurrentRateLimit(sendRateLimitKey), 10_000_000e6);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent(exchange, address(otcBuffer), Ethereum.USDT, 10_000_000e6);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     block.timestamp,
            normalizedClaimed: 0
        });

        assertEq(USDT.balanceOf(address(almProxy)), 0);
        assertEq(USDT.balanceOf(exchange),          10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(sendRateLimitKey), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));
    }

    function test_otcSend_usds() external {
        bytes32 sendRateLimitKey = mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDS);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(sendRateLimitKey, 10_000_000e18, 0);
        vm.stopPrank();

        deal(Ethereum.USDS, address(almProxy), 10_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(USDS.balanceOf(exchange),          0);

        assertEq(rateLimits.getCurrentRateLimit(sendRateLimitKey), 10_000_000e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent(exchange, address(otcBuffer), Ethereum.USDS, 10_000_000e18);

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 10_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     block.timestamp,
            normalizedClaimed: 0
        });

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.balanceOf(exchange),          10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(sendRateLimitKey), 0);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));
    }

    function test_otcSend_resetsNormalizedClaimed() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT), 10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        // Claim the full amount back so normalizedClaimed > 0 and the next swap is ready.
        deal(Ethereum.USDT, address(otcBuffer), 5_000_000e6);
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        _assertOTCState({
            normalizedSent    : 5_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 5_000_000e18
        });

        // A new send resets normalizedClaimed to zero and overwrites normalizedSent/sentTimestamp.
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1_000_000e6);

        _assertOTCState({
            normalizedSent    : 1_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 0
        });
    }

    function test_otcSend_highDecimalsPrecisionLoss() external {
        // A token with >18 decimals: _toNormalizedAmount divides by 10**decimals, truncating dust
        // below 18-decimal precision (see the NOTE in OTCFacet.send).
        ERC20 token = new ERC20(24);

        bytes32 sendRateLimitKey = mainnetController.otc_getSendRateLimitKey(exchange, address(token));

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(sendRateLimitKey, type(uint256).max, 0);
        vm.stopPrank();

        // 5m tokens plus a single base unit, the trailing base unit is below 18-decimal precision.
        uint256 amount = 5_000_000e24 + 1;

        token.mint(address(almProxy), amount);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, address(token), amount);

        assertEq(token.balanceOf(address(almProxy)), 0);
        assertEq(token.balanceOf(exchange),          amount);

        // normalizedSent = amount * 1e18 / 1e24, truncating the +1 base unit (precision loss).
        _assertOTCState({
            normalizedSent    : 5_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 0
        });
    }

}

contract MainnetController_OTC_Claim_Tests is OTC_TestBase {

    function test_otcClaim_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.otc_claim(exchange, address(1));
    }

    function test_otcClaim_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.otc_claim(exchange, address(1));
    }

    function test_otcClaim_assetZeroAddress() external {
        vm.expectRevert("OTCFacet/asset-zero-address");
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, address(0));
    }

    function test_otcClaim_bufferNotSet() external {
        vm.expectRevert("OTCFacet/buffer-not-set");
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, address(1));
    }

    function test_otcClaim_invalidAction() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));

        vm.expectRevert("OTCFacet/invalid-action");
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, address(1));
    }

    function test_otcClaim_transferFailed() external {
        address token = address(new MockTokenReturnFalse());

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, token), 1_000_000e6, 0);
        vm.stopPrank();

        deal(token, address(otcBuffer), 1_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(token, type(uint256).max);

        vm.expectRevert("OTCFacet/transferFrom-failed");
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, token);
    }

    function test_otcClaim_transferFailedOnNonStandardReturnData() external {
        address token = address(new MockTokenReturn64Bytes());

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, token), 1_000_000e6, 0);
        vm.stopPrank();

        vm.expectRevert("OTCFacet/transferFrom-failed");
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, token);
    }

    // NOTE: This test covers the case where token returns null for transferFrom
    function test_otcClaim_usdt() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(otcBuffer), 10_000_000e6);

        assertEq(USDT.balanceOf(address(almProxy)),  0);
        assertEq(USDT.balanceOf(address(otcBuffer)), 10_000_000e6);

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCClaimed(exchange, address(otcBuffer), Ethereum.USDT, 10_000_000e6);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDT.balanceOf(address(almProxy)),  10_000_000e6);
        assertEq(USDT.balanceOf(address(otcBuffer)), 0);

        _assertOTCState({
            normalizedSent:    0,  // Sent step not done, but this shows its not modified
            sentTimestamp:     0,  // Sent step not done, but this shows its not modified
            normalizedClaimed: 10_000_000e18
        });
    }

    function test_otcClaim_usds() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDS, address(otcBuffer), 10_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),  0);
        assertEq(USDS.balanceOf(address(otcBuffer)), 10_000_000e18);

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCClaimed(exchange, address(otcBuffer), Ethereum.USDS, 10_000_000e18);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(address(almProxy)),  10_000_000e18);
        assertEq(USDS.balanceOf(address(otcBuffer)), 0);

        _assertOTCState({
            normalizedSent:    0,  // Sent step not done, but this shows its not modified
            sentTimestamp:     0,  // Sent step not done, but this shows its not modified
            normalizedClaimed: 10_000_000e18
        });
    }

    function test_otcClaim_accumulatesNormalizedClaimed() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT), 10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        vm.stopPrank();

        deal(Ethereum.USDT, address(almProxy), 5_000_000e6);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 5_000_000e6);

        _assertOTCState({
            normalizedSent    : 5_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 0
        });

        // First partial claim.
        deal(Ethereum.USDT, address(otcBuffer), 2_000_000e6);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        _assertOTCState({
            normalizedSent    : 5_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 2_000_000e18
        });

        // Second partial claim accumulates on top of the first.
        deal(Ethereum.USDT, address(otcBuffer), 1_500_000e6);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        _assertOTCState({
            normalizedSent    : 5_000_000e18,
            sentTimestamp     : block.timestamp,
            normalizedClaimed : 3_500_000e18
        });
    }

}

contract MainnetController_OTC_E2ETests is OTC_TestBase {

    bytes32 internal usdtSendRateLimitKey;
    bytes32 internal usdsSendRateLimitKey;

    function setUp() public virtual override {
        super.setUp();

        usdtSendRateLimitKey = mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDT);
        usdsSendRateLimitKey = mainnetController.otc_getSendRateLimitKey(exchange,  Ethereum.USDS);

        vm.startPrank(Ethereum.SPARK_PROXY);

        mainnetController.otc_setBuffer(exchange, address(otcBuffer));

        rateLimits.setRateLimitData(usdtSendRateLimitKey, 10_000_000e6,  0);
        rateLimits.setRateLimitData(usdsSendRateLimitKey, 10_000_000e18, 0);

        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);

        vm.stopPrank();
    }

    function test_e2e_swapUSDTToUSDS() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        // Step 1: Send USDT to exchange

        assertEq(USDT.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(USDT.balanceOf(exchange),          0);

        assertEq(rateLimits.getCurrentRateLimit(usdtSendRateLimitKey), 10_000_000e6);

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDT,
            amount   : 10_000_000e6
        });

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);

        assertEq(USDT.balanceOf(address(almProxy)),  0);
        assertEq(USDT.balanceOf(exchange),           10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdtSendRateLimitKey), 0);

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(Ethereum.USDS, exchange, 9_980_000e18);

        vm.prank(exchange);
        USDS.transfer(address(otcBuffer), 9_980_000e18);

        assertEq(USDS.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        assertEq(USDS.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),  0);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCClaimed({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDS,
            amount   : 9_980_000e18
        });

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 9_980_000e18
        });

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        assertEq(USDS.balanceOf(address(otcBuffer)), 0);
        assertEq(USDS.balanceOf(address(almProxy)),  9_980_000e18);

        // Cannot do another swap
        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 1e18);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.otc_getClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        // Step 5: Swap another asset using the same rate limit

        uint256 currentRateLimit = rateLimits.getCurrentRateLimit(usdsSendRateLimitKey);

        assertGt(currentRateLimit, 200_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 9_980_000e18);
        assertEq(USDS.balanceOf(exchange),          0);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDS,
            amount   : 200_000e18
        });

        // Able to do another swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 200_000e18);

        assertEq(rateLimits.getCurrentRateLimit(usdsSendRateLimitKey), currentRateLimit - 200_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 9_780_000e18);
        assertEq(USDS.balanceOf(exchange),          200_000e18);

        // OTC state is reset
        _assertOTCState({
            normalizedSent:    200_000e18,
            sentTimestamp:     block.timestamp,
            normalizedClaimed: 0
        });
    }

    function test_e2e_swapUSDSToUSDT() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        deal(Ethereum.USDS, address(almProxy), 10_000_000e18);

        // Step 1: Send USDT to exchange

        assertEq(USDS.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(USDS.balanceOf(exchange),          0);

        assertEq(rateLimits.getCurrentRateLimit(usdsSendRateLimitKey), 10_000_000e18);

        _assertOTCState({
            normalizedSent:    0,
            sentTimestamp:     0,
            normalizedClaimed: 0
        });

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDS,
            amount   : 10_000_000e18
        });

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDS, 10_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.balanceOf(exchange),          10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(usdsSendRateLimitKey), 0);

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(Ethereum.USDT, exchange, 9_980_000e6);

        vm.prank(exchange);
        IERC20Like(Ethereum.USDT).transfer(address(otcBuffer), 9_980_000e6);

        assertEq(USDT.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        assertEq(USDT.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),  0);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCClaimed({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDT,
            amount   : 9_980_000e6
        });

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDT);

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 9_980_000e18
        });

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        assertEq(USDT.balanceOf(address(otcBuffer)), 0);
        assertEq(USDT.balanceOf(address(almProxy)),  9_980_000e6);

        // Cannot do another swap
        vm.expectRevert("OTCFacet/last-swap-not-returned");
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 1e6);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.otc_getClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.otc_getClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.otc_getClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));

        // Step 5: Swap another asset using the same rate limit

        uint256 currentRateLimit = rateLimits.getCurrentRateLimit(usdtSendRateLimitKey);

        assertGt(currentRateLimit, 200_000e6);

        assertEq(USDT.balanceOf(address(almProxy)), 9_980_000e6);
        assertEq(USDT.balanceOf(exchange),          0);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDT,
            amount   : 200_000e6
        });

        // Able to do another swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdtSendRateLimitKey), currentRateLimit - 200_000e6);

        assertEq(USDT.balanceOf(address(almProxy)), 9_780_000e6);
        assertEq(USDT.balanceOf(exchange),          200_000e6);

        // OTC state is reset
        _assertOTCState({
            normalizedSent:    200_000e18,
            sentTimestamp:     block.timestamp,
            normalizedClaimed: 0
        });
    }

}

contract MainnetController_OTC_GetClaimedWithRecharge_Tests is OTC_TestBase {

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDT),  10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDS),  10_000_000e18,     0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_getOTCClaimedWithRecharge_noSentTimestamp() external view {
        // Would return non-zero without early return, because it would use (block.timestamp - 0) * normalizedRate
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);
    }

    function test_getOTCClaimedWithRecharge() external {
        uint256 startingTimestamp = block.timestamp;

        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDT,
            amount   : 10_000_000e6
        });

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        vm.warp(startingTimestamp + 30 minutes);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 20_833.333333333333333200e18);

        deal(Ethereum.USDS, exchange, 5_500_000e18);

        vm.prank(exchange);
        USDS.transfer(address(otcBuffer), 5_500_000e18);

        // Doesn't change because no claim yet
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 20_833.333333333333333200e18);

        // Claiming increases claimed amount
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 5_500_000e18 + 20_833.333333333333333200e18);

        vm.warp(startingTimestamp + 1 days);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 5_500_000e18 + 1 days * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 6_499_999.999999999999993600e18);

        vm.warp(startingTimestamp + 10 days);

        // No ceiling on amount, not necessary because `isOtcSwapReady` will become true as soon as its above slippage.
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 5_500_000e18 + 10 days * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 15_499_999.999999999999936000e18);
    }

    function test_getOTCClaimedWithRecharge_zeroClaimThenNonZeroClaim() external {
        uint256 startingTimestamp = block.timestamp;

        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IOTCFacet.OTCSent({
            exchange : exchange,
            buffer   : address(otcBuffer),
            asset    : Ethereum.USDT,
            amount   : 10_000_000e6
        });

        // Execute OTC swap
        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        vm.warp(startingTimestamp + 30 minutes);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        // No effect on state because of zero claim
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        _assertOTCState({
            normalizedSent:    10_000_000e18,
            sentTimestamp:     startingTimestamp,
            normalizedClaimed: 0
        });

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));

        deal(Ethereum.USDS, exchange, 5_500_000e18);

        vm.prank(exchange);
        USDS.transfer(address(otcBuffer), 5_500_000e18);

        // Claiming increases claimed amount
        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 5_500_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days));
    }

}

contract MainnetController_OTC_IsSwapReady_Tests is OTC_TestBase {

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.otc_setBuffer(exchange, address(otcBuffer));
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDT),  10_000_000e6,      0);
        rateLimits.setRateLimitData(mainnetController.otc_getSendRateLimitKey(exchange, Ethereum.USDS),  10_000_000e18,     0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDT), type(uint256).max, 0);
        rateLimits.setRateLimitData(mainnetController.otc_getClaimRateLimitKey(exchange, Ethereum.USDS), type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_isOTCSwapReady_falseWithZeroSlippage() external {
        assertFalse(mainnetController.otc_getIsSwapReady(makeAddr("fake-exchange")));
    }

    function test_isOTCSwapReady() external {
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        vm.prank(allocator);
        mainnetController.otc_send(exchange, Ethereum.USDT, 10_000_000e6);

        deal(Ethereum.USDS, exchange, 9_995_000e18 - 1);

        vm.prank(exchange);
        USDS.transfer(address(otcBuffer), 9_995_000e18 - 1);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 0);

        vm.prank(allocator);
        mainnetController.otc_claim(exchange, Ethereum.USDS);

        assertEq(mainnetController.otc_getClaimWithRecharge(exchange), 9_995_000e18 - 1);

        assertFalse(mainnetController.otc_getIsSwapReady(exchange));

        skip(1 seconds);

        assertGt(mainnetController.otc_getClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.otc_getIsSwapReady(exchange));
    }

}
