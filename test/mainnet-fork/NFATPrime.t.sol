// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { NFATFacility } from "../../lib/nfat/src/NFATFacility.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { INFATPrimeFacet } from "../../src/facets/nfat-prime/INFATPrimeFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract NFATPrime_TestBase is ForkTestBase {

    NFATFacility internal facility;
    address      internal facilityRecipient;
    address      internal issuer;

    bytes32 internal subscribeKey;
    bytes32 internal withdrawKey;
    bytes32 internal collectKey;

    function setUp() public virtual override {
        super.setUp();

        facilityRecipient = makeAddr("facilityRecipient");
        issuer            = makeAddr("issuer");

        facility = new NFATFacility(Ethereum.USDS, "Test NFAT", "TNFAT");
        facility.file("recipient", facilityRecipient);
        facility.kiss(issuer);

        subscribeKey = mainnetController.nfatPrime_getSubscribeRateLimitKey(address(facility), Ethereum.USDS);
        withdrawKey  = mainnetController.nfatPrime_getWithdrawRateLimitKey(address(facility));
        collectKey   = mainnetController.nfatPrime_getCollectRateLimitKey(address(facility));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(subscribeKey);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);
        rateLimits.setUnlimitedRateLimitData(collectKey);
        vm.stopPrank();
    }

}

contract MainnetController_NFATPrime_Subscribe_Tests is NFATPrime_TestBase {

    uint256 internal constant SUBSCRIBE_AMOUNT = 1_000_000e18;

    function setUp() public override {
        super.setUp();

        deal(Ethereum.USDS, address(almProxy), SUBSCRIBE_AMOUNT);
    }

    function test_subscribe_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribe_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribe_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribe_rateLimitBoundary() external {
        uint256 limit = 100_000e18;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, limit, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), limit + 1, "");

        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), limit, "");
    }

    function test_subscribe() external {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18 + SUBSCRIBE_AMOUNT);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, 5_000_000e18, 0);

        assertEq(usds.balanceOf(address(facility)),                    0);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18 + SUBSCRIBE_AMOUNT);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(facility.deposits(address(almProxy)),                 0);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),         5_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit INFATPrimeFacet.NFATPrimeSubscribe(address(facility), SUBSCRIBE_AMOUNT, "");

        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),                    SUBSCRIBE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(facility.deposits(address(almProxy)),                 SUBSCRIBE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),         5_000_000e18 - SUBSCRIBE_AMOUNT);
    }

    function test_subscribe_withData() external {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18 + SUBSCRIBE_AMOUNT);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, 5_000_000e18, 0);

        bytes memory data = abi.encode("agreement-id-123");

        assertEq(usds.balanceOf(address(facility)),                    0);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18 + SUBSCRIBE_AMOUNT);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(facility.deposits(address(almProxy)),                 0);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),         5_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit INFATPrimeFacet.NFATPrimeSubscribe(address(facility), SUBSCRIBE_AMOUNT, data);

        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, data);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),                    SUBSCRIBE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(facility.deposits(address(almProxy)),                 SUBSCRIBE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),         5_000_000e18 - SUBSCRIBE_AMOUNT);
    }

}

contract MainnetController_NFATPrime_Withdraw_Tests is NFATPrime_TestBase {

    uint256 internal constant SUBSCRIBE_AMOUNT = 1_000_000e18;

    function setUp() public override {
        super.setUp();

        deal(Ethereum.USDS, address(almProxy), SUBSCRIBE_AMOUNT);

        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");
    }

    function test_withdraw_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatPrime_withdraw(address(facility), SUBSCRIBE_AMOUNT);
    }

    function test_withdraw_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.nfatPrime_withdraw(address(facility), SUBSCRIBE_AMOUNT);
    }

    function test_withdraw_zeroAmount() external {
        vm.expectRevert("NFATPrimeFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.nfatPrime_withdraw(address(facility), 0);
    }

    function test_withdraw_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(withdrawKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatPrime_withdraw(address(facility), SUBSCRIBE_AMOUNT);
    }

    function test_withdraw_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(withdrawKey, 500_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatPrime_withdraw(address(facility), 500_000e18 + 1);

        vm.prank(allocator);
        mainnetController.nfatPrime_withdraw(address(facility), 500_000e18);
    }

    function test_withdraw() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, 0);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(usds.balanceOf(address(facility)),           SUBSCRIBE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),           1_000_000e18);
        assertEq(facility.deposits(address(almProxy)),        SUBSCRIBE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit INFATPrimeFacet.NFATPrimeWithdraw(address(facility), SUBSCRIBE_AMOUNT);

        vm.prank(allocator);
        mainnetController.nfatPrime_withdraw(address(facility), SUBSCRIBE_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),           0);
        assertEq(usds.balanceOf(address(almProxy)),           1_000_000e18 + SUBSCRIBE_AMOUNT);
        assertEq(facility.deposits(address(almProxy)),        0);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - SUBSCRIBE_AMOUNT);
    }

}

contract MainnetController_NFATPrime_Collect_Tests is NFATPrime_TestBase {

    uint256 internal constant REPAY_AMOUNT     = 1_050_000e18;
    uint256 internal constant SUBSCRIBE_AMOUNT = 1_000_000e18;
    uint256 internal constant TOKEN_ID         = 1;

    function setUp() public override {
        super.setUp();

        deal(Ethereum.USDS, address(almProxy), SUBSCRIBE_AMOUNT);

        // Subscribe and issue so the proxy holds an NFT
        vm.prank(allocator);
        mainnetController.nfatPrime_subscribe(address(facility), SUBSCRIBE_AMOUNT, "");

        vm.prank(issuer);
        facility.issue(address(almProxy), TOKEN_ID, SUBSCRIBE_AMOUNT);

        assertEq(facility.ownerOf(TOKEN_ID), address(almProxy));

        deal(Ethereum.USDS, issuer, REPAY_AMOUNT);

        vm.startPrank(issuer);
        usds.approve(address(facility), REPAY_AMOUNT);
        facility.repay(TOKEN_ID, REPAY_AMOUNT);
        vm.stopPrank();
    }

    function test_collect_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 1_000_000e18);
    }

    function test_collect_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 1_000_000e18);
    }

    function test_collect_zeroAmount() external {
        vm.expectRevert("NFATPrimeFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 0);
    }

    function test_collect_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(collectKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 1_000_000e18);
    }

    function test_collect_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(collectKey, 1_000_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 1_000_000e18 + 1);

        vm.prank(allocator);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, 1_000_000e18);
    }

    function test_collect() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(collectKey, 2_000_000e18, 0);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        uint256 collectAmount = 1_000_000e18;

        assertEq(usds.balanceOf(address(facility)),          REPAY_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),          1_000_000e18);
        assertEq(facility.collectable(TOKEN_ID),             REPAY_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(collectKey), 2_000_000e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit INFATPrimeFacet.NFATPrimeCollect(address(facility), TOKEN_ID, collectAmount);

        vm.prank(allocator);
        mainnetController.nfatPrime_collect(address(facility), TOKEN_ID, collectAmount);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),          REPAY_AMOUNT - collectAmount);
        assertEq(usds.balanceOf(address(almProxy)),          1_000_000e18 + collectAmount);
        assertEq(facility.collectable(TOKEN_ID),             REPAY_AMOUNT - collectAmount);
        assertEq(rateLimits.getCurrentRateLimit(collectKey), 2_000_000e18 - collectAmount);
    }

}
