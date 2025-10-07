// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock }      from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IERC20 as OzIERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

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

        mainnetController.setMaxSlippage(exchange, 0.9995e18);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        vm.stopPrank();
    }

    function _assertOtcState(
        uint256 sent18,
        uint256 sentTimestamp,
        uint256 claimed18
    )
        internal view
    {
        ( ,, uint256 sent18_, uint256 sentTimestamp_, uint256 claimed18_ )
            = mainnetController.otcs(exchange);

        assertEq(sent18_,        sent18);
        assertEq(sentTimestamp_, sentTimestamp);
        assertEq(claimed18_,     claimed18);
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

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usdt), buffer, 4_997_500e6 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        deal(address(usdt), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18);

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

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usds), buffer, 4_997_500e18 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usds), 1e18);

        deal(address(usds), buffer, 1);

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18);

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

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usdt), buffer, 4_997_500e6 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usdt));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18 - 1e12);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        skip(1 seconds);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18);

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

        // 5m * 99.95% slippage = 4.9975m
        deal(address(usds), buffer, 4_997_500e18 - 1);

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds));

        // Six decimal asset conversion
        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18 - 1);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usds), 1e18);

        skip(1 seconds);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 4_997_500e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

}

contract MainnetControllerotcSendSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSend_usdt() external {
        deal(address(usdt), address(almProxy), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: uint48(block.timestamp),
            claimed18:     0
        });

        assertEq(usdt.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(exchange)), 10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_otcSend_usds() external {
        deal(address(usds), address(almProxy), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: uint48(block.timestamp),
            claimed18:     0
        });

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(exchange)), 10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

contract MainnetControllerOTCClaimFailureTests is MainnetControllerOTCSwapBase {

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

        vm.prank(relayer);
        vm.expectRevert("MainnetController/asset-to-claim-zero");
        mainnetController.otcClaim(exchange, address(0));
    }

    function test_otcClaim_otcBufferNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcClaim(makeAddr("fake-exchange"), address(1));
    }

}

contract MainnetControllerOTCClaimSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcClaim_usdt() external {
        ( address octBuffer,,,, ) = mainnetController.otcs(exchange);

        deal(address(usdt), address(octBuffer), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)),  0);
        assertEq(usdt.balanceOf(address(octBuffer)), 10_000_000e6);

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(octBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcClaim(exchange, address(usdt));

        assertEq(usdt.balanceOf(address(almProxy)),  10_000_000e6);
        assertEq(usdt.balanceOf(address(octBuffer)), 0);

        _assertOtcState({
            sent18:        0,  // Sent step not done, but this shows its not modified
            sentTimestamp: 0,  // Sent step not done, but this shows its not modified
            claimed18:     10_000_000e18
        });
    }

    function test_otcClaim_usds() external {
        ( address octBuffer,,,, ) = mainnetController.otcs(exchange);

        deal(address(usds), address(octBuffer), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(octBuffer)), 10_000_000e18);

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(octBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcClaim(exchange, address(usds));

        assertEq(usds.balanceOf(address(almProxy)),  10_000_000e18);
        assertEq(usds.balanceOf(address(octBuffer)), 0);

        _assertOtcState({
            sent18:        0,  // Sent step not done, but this shows its not modified
            sentTimestamp: 0,  // Sent step not done, but this shows its not modified
            claimed18:     10_000_000e18
        });
    }

}

contract MainnetControllerE2ETests is MainnetControllerOTCSwapBase {

    function test_e2e_swapUsdtToUsds() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        ( address otcBuffer,,,, ) = mainnetController.otcs(exchange);

        deal(address(usdt), address(almProxy), 10_000_000e6);

        // Step 1: Send USDT to exchange

        assertEq(usdt.balanceOf(address(almProxy)), 10_000_000e6);
        assertEq(usdt.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usdt), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)),  0);
        assertEq(usdt.balanceOf(address(exchange)),  10_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(address(usds), address(exchange), 9_980_000e18);

        vm.prank(exchange);
        usds.transfer(otcBuffer, 9_980_000e18);

        assertEq(usds.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usds.balanceOf(address(otcBuffer)), 9_980_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usds), 9_980_000e18, 9_980_000e18);
        mainnetController.otcClaim(exchange, address(usds));

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     9_980_000e18
        });

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usds.balanceOf(address(otcBuffer)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  9_980_000e18);

        // Cannot do another swap
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usds), 1e18);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        // Able to do another swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usds), 1e18);
    }

    function test_e2e_swapUsdsToUsdt() external {
        uint48 startingTimestamp = uint48(block.timestamp);

        ( address otcBuffer,,,, ) = mainnetController.otcs(exchange);

        deal(address(usds), address(almProxy), 10_000_000e18);

        // Step 1: Send USDT to exchange

        assertEq(usds.balanceOf(address(almProxy)), 10_000_000e18);
        assertEq(usds.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        _assertOtcState({
            sent18:        0,
            sentTimestamp: 0,
            claimed18:     0
        });

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSend(exchange, address(usds), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(exchange)),  10_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

        skip(10 minutes); // Simulate realistic passage of time

        // Recharge starts without any claim after send
        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            10 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 6_944e18, 1e18);

        // Step 2: Send USDS to buffer from exchange under slippage

        deal(address(usdt), address(exchange), 9_980_000e6);

        vm.prank(exchange);
        SafeERC20.safeTransfer(OzIERC20(address(usdt)), otcBuffer, 9_980_000e6);

        assertEq(usdt.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        skip(1 minutes); // Simulate realistic passage of time

        // Step 3: Claim OTC funds

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     0
        });

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            11 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 7_638e18, 1e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usdt.balanceOf(address(otcBuffer)), 9_980_000e6);
        assertEq(usdt.balanceOf(address(almProxy)),  0);

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usdt), 9_980_000e6, 9_980_000e18);
        mainnetController.otcClaim(exchange, address(usdt));

        _assertOtcState({
            sent18:        10_000_000e18,
            sentTimestamp: startingTimestamp,
            claimed18:     9_980_000e18
        });

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            9_980_000e18 + (11 minutes) * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 9_987_638e18, 1e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usdt.balanceOf(address(otcBuffer)), 0);
        assertEq(usdt.balanceOf(address(almProxy)),  9_980_000e6);

        // Cannot do another swap
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSend(exchange, address(usdt), 1e6);

        // Step 4: Demonstrate how recharging can bring an OTC swap above slippage requirements over time

        skip(19 minutes);

        assertEq(
            mainnetController.getOtcClaimWithRecharge(exchange),
            9_980_000e18 + 30 minutes * (uint256(1_000_000e18) / 1 days)
        );

        assertApproxEqAbs(mainnetController.getOtcClaimWithRecharge(exchange), 10_000_833e18, 1e18);

        assertGt(mainnetController.getOtcClaimWithRecharge(exchange), 9_995_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        // Able to do another swap
        vm.prank(relayer);
        mainnetController.otcSend(exchange, address(usdt), 1e6);
    }

}

// contract MainnetControlerGetOtcClaimedWithRechargeTests is MainnetControllerOTCSwapBase {

//     function test_getOtcClaimedWithRecharge() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         deal(address(usdt), address(almProxy), 10_000_000e6);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(
//             exchange,
//             address(usdt),
//             10_000_000e6
//         );

//         skip(30 minutes);

//         deal(address(usds), address(exchange), 5_500_000e18);

//         vm.prank(exchange);
//         usds.transfer(address(otcBuffer), 5_500_000e18);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

//         // Claiming starts the recharge
//         vm.prank(relayer);
//         mainnetController.otcClaim(exchange, address(usds));

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18);

//         skip(1 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18 + 1 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 6_499_999.999999999999993600e18);

//         skip(1 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18 + 2 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 7_499_999.999999999999987200e18);

//         skip(2 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18 + 4 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 9_499_999.999999999999974400e18);

//         skip(1 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18 + 5 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 10_499999.999999999999968000e18);

//         skip(10 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 5_500_000e18 + 15 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 20_499_999.999999999999904000e18);
//     }

//     function test_getOtcClaimedWithRecharge_zeroClaimThenNonZeroClaim() external {
//         vm.prank(Ethereum.SPARK_PROXY);
//         mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

//         deal(address(usdt), address(almProxy), 10_000_000e6);

//         // Execute OTC swap
//         vm.prank(relayer);
//         vm.expectEmit(address(mainnetController));
//         emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
//         mainnetController.otcSend(
//             exchange,
//             address(usdt),
//             10_000_000e6
//         );

//         skip(30 minutes);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

//         _assertOtcState({
//             sent18:        10_000_000e18,
//             sentTimestamp: 0,
//             claimed18:     0
//         });

//         // Claiming starts the recharge, even with zero claimed amount
//         vm.prank(relayer);
//         mainnetController.otcClaim(exchange, address(usds));

//         _assertOtcState({
//             sent18:        10_000_000e18,
//             sentTimestamp: 0,
//             claimed18:     0nt48(block.timestamp)
//         });

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 0);

//         skip(1 days);

//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 1 days * (uint256(1_000_000e18) / 1 days));
//         assertEq(mainnetController.getOtcClaimWithRecharge(exchange), 1_499_999.999999999999993600e18);
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