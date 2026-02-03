// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC20Mock }       from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { OTCLib } from "../../src/libraries/OTCLib.sol";

import { OTCBuffer }      from "../../src/OTCBuffer.sol";
import { makeAddressKey } from "../../src/RateLimitHelpers.sol";
import { RateLimits }     from "../../src/RateLimits.sol";

import { MockTokenReturnFalse } from "../mocks/Mocks.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    // Purposely not returning bool to avoid reverts on transfers.
    function transfer(address to, uint256 amount) external;

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

    bytes32 internal constant LIMIT_OTC_SWAP = keccak256("LIMIT_OTC_SWAP");

    bytes32 internal key;

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
        otcBuffer.approve(address(usdt), type(uint256).max);
        otcBuffer.approve(address(usds), type(uint256).max);
        vm.stopPrank();

        key = makeAddressKey(LIMIT_OTC_SWAP, exchange);

        vm.startPrank(Ethereum.SPARK_PROXY);

        // NOTE: This is asset agnostic but USD based
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        mainnetController.setMaxSlippage(exchange, 0.9995e18);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);
        mainnetController.setOTCWhitelistedAsset(exchange, address(usdt), true);
        mainnetController.setOTCWhitelistedAsset(exchange, address(usds), true);

        vm.stopPrank();
    }

    function _assertOTCState(uint256 sent18, uint256 sentTimestamp, uint256 claimed18)
        internal
        view
    {
        (
            ,
            ,
            uint256 sent18_,
            uint256 sentTimestamp_,
            uint256 claimed18_
        ) = mainnetController.otcs(exchange);

        assertEq(sent18_,        sent18);
        assertEq(sentTimestamp_, sentTimestamp);
        assertEq(claimed18_,     claimed18);
    }

}

// NOTE: This test requires the send to be executed first which requires ForkTestBase,
//       therefore it is placed here instead of Admin.t.sol.
contract MainnetController_SetOTCBuffer_Tests is OTC_TestBase {

    function test_setOTCBuffer_swapInProgress() external {
        deal(address(usdt), address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 5_000_000e6);

        vm.expectRevert("OTCLib/swap-in-progress");
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, makeAddr("new-buffer"));
    }

}

contract MainnetController_OTCSend_Tests is OTC_TestBase {

    function test_otcSend_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.otcSend(exchange, address(1), 1e18);
    }

    function test_otcSend_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcSend(exchange, address(1), 1e18);
    }

    function test_otcSend_assetToSendZero() external {
        vm.expectRevert("OTCLib/asset-to-send-zero");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(0), 1e18);
    }

    function test_otcSend_amountToSendZero() external {
        vm.expectRevert("OTCLib/amount-to-send-zero");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 0);
    }

    function test_otcSend_assetNotWhitelisted() external {
        vm.expectRevert("OTCLib/asset-not-whitelisted");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(1), 1e18);
    }

    function test_otcSend_rateLimitZero() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(makeAddr("fake-exchange"), address(otcBuffer));
        mainnetController.setOTCWhitelistedAsset(makeAddr("fake-exchange"), address(usdt), true);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.otcSend(makeAddr("fake-exchange"), address(usdt), 1e18);
    }

    function test_otcSend_usdt_rateLimitedBoundary() external {
        deal(address(usdt), address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);
    }

    function test_otcSend_usds_rateLimitedBoundary() external {
        deal(address(usds), address(almProxy), 10_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);
    }

    function test_otcSend_transferFailed() external {
        address token = address(new MockTokenReturnFalse());

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCWhitelistedAsset(exchange, token, true);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        deal(token, address(almProxy), 1_000_000e6);

        vm.expectRevert("OTCLib/transfer-failed");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, token, 1_000_000e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usdt() external {
        deal(address(usdt), address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 5_000_000e6);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        ( address buffer, , , , ) = mainnetController.otcs(exchange);

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usdt), buffer, 4_997_500e6 - 1);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        deal(address(usdt), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_noRecharge_usds() external {
        deal(address(usds), address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 5_000_000e18);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        ( address buffer, , , , ) = mainnetController.otcs(exchange);

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usds), buffer, 4_997_500e18 - 1);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);

        deal(address(usds), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usdt() external {
        deal(address(usdt), address(almProxy), 5_000_000e6);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 5_000_000e6);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        ( address buffer, , , , ) = mainnetController.otcs(exchange);

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usdt), buffer, 4_997_500e6 - 1);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        skip(1 seconds);

        assertGt(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

    function test_otcSend_lastSwapNotReturnedBoundary_recharge_usds() external {
        deal(address(usds), address(almProxy), 5_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 5_000_000e18);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        ( address buffer, , , , ) = mainnetController.otcs(exchange);

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usds), buffer, 4_997_500e18 - 1);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        // Six decimal asset conversion
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);

        skip(1 seconds);

        assertGt(mainnetController.getOTCClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

    // NOTE: This test covers the case where token returns null for transfer
    function test_otcSend_usdt() external {
        deal(address(usdt), address(almProxy), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: uint48(block.timestamp),
            claimed18:     0
        });

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(exchange)), 10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));
    }

    function test_otcSend_usds() external {
        deal(address(usds), address(almProxy), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: uint48(block.timestamp),
            claimed18:     0
        });

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(exchange)), 10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));
    }

}

contract MainnetController_OTCClaim_Tests is OTC_TestBase {

    function test_otcClaim_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.otcClaim(exchange, address(1));
    }

    function test_otcClaim_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcClaim(exchange, address(1));
    }

    function test_otcClaim_assetToClaimZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        vm.expectRevert("OTCLib/asset-to-claim-zero");
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(0));
    }

    function test_otcClaim_otcBufferNotSet() external {
        vm.expectRevert("OTCLib/otc-buffer-not-set");
        vm.prank(relayer);
        mainnetController.otcClaim(makeAddr("fake-exchange"), address(1));
    }

    function test_otcClaim_assetNotWhitelisted() external {
        vm.expectRevert("OTCLib/asset-not-whitelisted");
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(1));
    }

    function test_otcClaim_transferFailed() external {
        address token = address(new MockTokenReturnFalse());

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCWhitelistedAsset(exchange, token, true);

        deal(token, address(otcBuffer), 1_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(token, type(uint256).max);

        vm.expectRevert("OTCLib/transferFrom-failed");
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, token);
    }

    // NOTE: This test covers the case where token returns null for transferFrom
    function test_otcClaim_usdt() external {
        ( address otcBuffer, , , , ) = mainnetController.otcs(exchange);

        deal(address(usdt), address(otcBuffer), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)),  0);
        assertEq(usdt.balanceOf(address(otcBuffer)), 10_000_000e6);

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCClaimed(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdt.balanceOf(address(almProxy)),  10_000_000e6);
        assertEq(usdt.balanceOf(address(otcBuffer)), 0);

        _assertOTCState({
            sent18:        0,  // Sent step not done, but this shows its not modified
            sentTimestamp: 0,  // Sent step not done, but this shows its not modified
            claimed18:     10_000_000e18
        });
    }

    function test_otcClaim_usds() external {
        ( address otcBuffer, , , , ) = mainnetController.otcs(exchange);

        deal(address(usds), address(otcBuffer), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(otcBuffer)), 10_000_000e18);

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCClaimed(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)),  10_000_000e18);
        assertEq(usds.balanceOf(address(otcBuffer)), 0);

        _assertOTCState({
            sent18:        0,  // Sent step not done, but this shows its not modified
            sentTimestamp: 0,  // Sent step not done, but this shows its not modified
            claimed18:     10_000_000e18
        });
    }

}

contract MainnetController_OTC_E2ETests is OTC_TestBase {

    function test_e2e_swapUSDTToUSDS() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        ( address otcBuffer, , , , ) = mainnetController.otcs(exchange);

        deal(address(usdt), address(almProxy), 10_000_000e6);

        // Step 1: Send USDT to exchange

        assertEq(usdt.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)),  0);
        assertEq(usdt.balanceOf(address(exchange)),  10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(address(usds), address(exchange), 9_980_000e18);

        vm.prank(exchange);
        usds.transfer(otcBuffer, 9_980_000e18);

        assertEq(usds.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        assertEq(usds.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCClaimed(exchange, address(otcBuffer), address(usds), 9_980_000e18, 9_980_000e18);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     9_980_000e18
        });

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        assertEq(usds.balanceOf(address(otcBuffer)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  9_980_000e18);

        // Cannot do another swap
        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.getOTCClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        // Step 5: Swap another asset using the same rate limit

        uint256 currentRateLimit = rateLimits.getCurrentRateLimit(key);

        assertGt(currentRateLimit, 200_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 9_980_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usds), 200_000e18, 200_000e18);

        // Able to do another swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 200_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), currentRateLimit - 200_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  9_780_000e18);
        assertEq(usds.balanceOf(address(exchange)),  200_000e18);

        // OTC state is reset
        _assertOTCState({
            sent18:        200_000e18,
            sentTimestamp: block.timestamp,
            claimed18:     0
        });
    }

    function test_e2e_swapUSDSToUSDT() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        ( address otcBuffer, , , , ) = mainnetController.otcs(exchange);

        deal(address(usds), address(almProxy), 10_000_000e18);

        // Step 1: Send USDT to exchange

        assertEq(usds.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        _assertOTCState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(exchange)),  10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(address(usdt), address(exchange), 9_980_000e6);

        vm.prank(exchange);
        IERC20Like(address(usdt)).transfer(otcBuffer, 9_980_000e6);

        assertEq(usdt.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        assertEq(usdt.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCClaimed(exchange, address(otcBuffer), address(usdt), 9_980_000e6, 9_980_000e18);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     9_980_000e18
        });

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        assertEq(usdt.balanceOf(address(otcBuffer)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  9_980_000e6);

        // Cannot do another swap
        vm.expectRevert("OTCLib/last-swap-not-returned");
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.getOTCClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOTCClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.getOTCClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));

        // Step 5: Swap another asset using the same rate limit

        uint256 currentRateLimit = rateLimits.getCurrentRateLimit(key);

        assertGt(currentRateLimit, 200_000e18);

        assertEq(usdt.balanceOf(address(almProxy)), 9_980_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usdt), 200_000e6, 200_000e18);

        // Able to do another swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 200_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), currentRateLimit - 200_000e18);

        assertEq(usdt.balanceOf(address(almProxy)),  9_780_000e6);
        assertEq(usdt.balanceOf(address(exchange)),  200_000e6);

        // OTC state is reset
        _assertOTCState({
            sent18:        200_000e18,
            sentTimestamp: block.timestamp,
            claimed18:     0
        });
    }

}

contract MainnetController_GetOTCClaimedWithRecharge_Tests is OTC_TestBase {

    function test_getOTCClaimedWithRecharge_noSentTimestamp() external view {
        // Would return non-zero without early return, because it would use (block.timestamp - 0) * rechargeRate18
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);
    }

    function test_getOTCClaimedWithRecharge_test() external {
        uint256 startingTimestamp = block.timestamp;

        deal(address(usdt), address(almProxy), 10_000_000e6);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(
            exchange,
            address(usdt),
            10_000_000e6
        );

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        vm.warp(startingTimestamp + 30 minutes);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 20_833.333333333333333200e18);

        deal(address(usds), address(exchange), 5_500_000e18);

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 5_500_000e18);

        // Doesn't change because no claim yet
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 20_833.333333333333333200e18);

        // Claiming increases claimed amount
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 5_500_000e18 + 20_833.333333333333333200e18);

        vm.warp(startingTimestamp + 1 days);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 5_500_000e18 + 1 days * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 6_499_999.999999999999993600e18);

        vm.warp(startingTimestamp + 10 days);

        // No cieling on amount, not necessary because isOTCSwapReady will become true as soon as its above slippage
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 5_500_000e18 + 10 days * (uint256(1_000_000e18) / 1 days));
        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 15_499_999.999999999999936000e18);
    }

    function test_getOTCClaimedWithRecharge_zeroClaimThenNonZeroClaim() external {
        uint256 startingTimestamp = block.timestamp;

        deal(address(usdt), address(almProxy), 10_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        mainnetController.otcSend(
            exchange,
            address(usdt),
            10_000_000e6
        );

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        vm.warp(startingTimestamp + 30 minutes);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        // No effect on state because of zero claim
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        _assertOTCState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 30 minutes * (uint256(1_000_000e18) / 1 days));

        deal(address(usds), address(exchange), 5_500_000e18);

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 5_500_000e18);

        // Claiming increases claimed amount
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 5_500_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days));
    }

}

contract MainnetController_IsOTCSwapReady_Tests is OTC_TestBase {

    function test_isOTCSwapReady_falseWithZeroSlippage() external {
        assertFalse(mainnetController.isOTCSwapReady(makeAddr("fake-exchange")));
    }

    function test_isOTCSwapReady() external {
        deal(address(usdt), address(almProxy), 10_000_000e6);

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        deal(address(usds), address(exchange), 9_995_000e18 - 1);

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 9_995_000e18 - 1);

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 0);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOTCClaimWithRecharge(exchange), 9_995_000e18 - 1);

        assertFalse(mainnetController.isOTCSwapReady(address(exchange)));

        skip(1 seconds);

        assertGt(mainnetController.getOTCClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.isOTCSwapReady(address(exchange)));
    }

}
