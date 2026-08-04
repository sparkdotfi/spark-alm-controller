// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { NFATFacility } from "../../lib/nfat/src/NFATFacility.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { INFATHaloFacet } from "../../src/facets/nfat-halo/INFATHaloFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract NFATHalo_TestBase is ForkTestBase {

    NFATFacility internal facility;

    address internal subscriber;

    bytes32 internal issueKey;
    bytes32 internal repayPrincipalKey;
    bytes32 internal repayInterestKey;

    uint256 internal constant MAX_ANNUAL_GROWTH_RATE = 0.20e18;  // 20% APR
    uint256 internal constant SUBSCRIBE_AMOUNT       = 2_000_000e18;
    uint256 internal constant TOKEN_ID               = 1;

    function setUp() public virtual override {
        super.setUp();

        subscriber = makeAddr("subscriber");

        facility = new NFATFacility(Ethereum.USDS, "Test NFAT", "TNFAT");

        // Halo issue requires recipient == ALMProxy so the principal lands back in our custody
        // and the rate-limit delta can be measured against the ALMProxy balance.
        facility.file("recipient", address(almProxy));

        // Halo ALMProxy must be a bud on the facility because the facet calls
        // facility.issue / facility.repay via almProxy.doCall.
        facility.kiss(address(almProxy));

        issueKey          = mainnetController.nfatHalo_getIssueRateLimitKey(address(facility),          subscriber);
        repayPrincipalKey = mainnetController.nfatHalo_getRepayPrincipalRateLimitKey(address(facility), Ethereum.USDS);
        repayInterestKey  = mainnetController.nfatHalo_getRepayInterestRateLimitKey(address(facility),  Ethereum.USDS);

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setUnlimitedRateLimitData(issueKey);
        rateLimits.setUnlimitedRateLimitData(repayPrincipalKey);
        rateLimits.setUnlimitedRateLimitData(repayInterestKey);

        mainnetController.nfatHalo_setMaxAnnualGrowthRate(address(facility), MAX_ANNUAL_GROWTH_RATE);

        vm.stopPrank();

        deal(Ethereum.USDS, subscriber, SUBSCRIBE_AMOUNT);

        vm.startPrank(subscriber);
        usds.approve(address(facility), SUBSCRIBE_AMOUNT);
        facility.subscribe(SUBSCRIBE_AMOUNT, "");
        vm.stopPrank();
    }

    function _assertFacilityState(
        address facility,
        uint256 expectedInterestIndex,
        uint256 expectedLastUpdated
    ) internal {
        (
            uint256 interestIndex,
            uint256 lastUpdated
        ) = mainnetController.nfatHalo_getFacilityState(facility);

        assertEq(interestIndex, expectedInterestIndex);
        assertEq(lastUpdated,   expectedLastUpdated);
    }

    function _assertPosition(
        address facility,
        uint256 tokenId,
        bool    expectedIssued,
        uint256 expectedOutstandingPrincipal,
        uint256 expectedMaxOutstandingInterest,
        uint256 expectedInterestIndex
    ) internal {
        (
            bool    issued,
            uint256 outstandingPrincipal,
            uint256 maxOutstandingInterest,
            uint256 interestIndex
        ) = mainnetController.nfatHalo_getPosition(facility, tokenId);

        assertEq(issued,                 expectedIssued);
        assertEq(outstandingPrincipal,   expectedOutstandingPrincipal);
        assertEq(maxOutstandingInterest, expectedMaxOutstandingInterest);
        assertEq(interestIndex,          expectedInterestIndex);
    }

}

contract MainnetController_NFATHalo_Issue_Tests is NFATHalo_TestBase {

    uint256 internal constant ISSUE_AMOUNT = 1_000_000e18;

    function test_issue_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);
    }

    function test_issue_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));

        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);
    }

    function test_issue_zeroAmount() external {
        vm.expectRevert("NFATHaloFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, 0);
    }

    function test_issue_alreadyIssued() external {
        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);

        vm.expectRevert("NFATHaloFacet/position-exists");
        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);
    }

    function test_issue_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(issueKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);
    }

    function test_issue_rateLimitBoundary() external {
        uint256 limit = 100_000e18;

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(issueKey, limit, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, limit + 1);

        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, limit);
    }

    function test_issue() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(issueKey, 5_000_000e18, 0);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(usds.balanceOf(address(facility)),        SUBSCRIBE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),        1_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(issueKey), 5_000_000e18);

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : false,
            expectedOutstandingPrincipal   : 0,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloIssue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);

        vm.record();

        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),        SUBSCRIBE_AMOUNT - ISSUE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),        1_000_000e18 + ISSUE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(issueKey), 5_000_000e18 - ISSUE_AMOUNT);

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });
    }

    function test_issue_multipleTokens() external {
        uint256 firstAmount  = ISSUE_AMOUNT / 4;
        uint256 secondAmount = ISSUE_AMOUNT - firstAmount;

        vm.startPrank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, 1, firstAmount);
        mainnetController.nfatHalo_issue(address(facility), subscriber, 2, secondAmount);
        vm.stopPrank();

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : 1,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : firstAmount,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : 2,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : secondAmount,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });
    }

}

abstract contract NFATHalo_PostIssue_TestBase is NFATHalo_TestBase {

    uint256 internal constant ISSUE_AMOUNT = 1_000_000e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(allocator);
        mainnetController.nfatHalo_issue(address(facility), subscriber, TOKEN_ID, ISSUE_AMOUNT);
    }

}

contract MainnetController_NFATHalo_RepayPrincipal_Tests is NFATHalo_PostIssue_TestBase {

    function test_repayPrincipal_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 1);
    }

    function test_repayPrincipal_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 1);
    }

    function test_repayPrincipal_zeroAmount() external {
        vm.expectRevert("NFATHaloFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 0);
    }

    function test_repayPrincipal_positionNotFound() external {
        vm.expectRevert("NFATHaloFacet/position-not-found");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), 99, 1);
    }

    function test_repayPrincipal_principalExceededBoundary() external {
        vm.prank(allocator);
        vm.expectRevert("NFATHaloFacet/principal-exceeded");
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, ISSUE_AMOUNT + 1);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, ISSUE_AMOUNT);
    }

    function test_repayPrincipal_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayPrincipalKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 1);
    }

    function test_repayPrincipal_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayPrincipalKey, 50_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 50_000e18 + 1);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 50_000e18);
    }

    function test_repayPrincipal() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayPrincipalKey, 5_000_000e18, 0);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18 + ISSUE_AMOUNT);

        uint256 startTimestamp = vm.getBlockTimestamp();

        vm.warp(startTimestamp + 180 days);

        assertEq(usds.balanceOf(address(facility)),                 SUBSCRIBE_AMOUNT - ISSUE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),                 1_000_000e18 + ISSUE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(repayPrincipalKey), 5_000_000e18);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayPrincipal(address(facility), TOKEN_ID, ISSUE_AMOUNT);

        vm.record();

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, ISSUE_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),                    SUBSCRIBE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(rateLimits.getCurrentRateLimit(repayPrincipalKey),    5_000_000e18 - ISSUE_AMOUNT);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : 0,
            expectedMaxOutstandingInterest : 98_630.136986301369e18,
            expectedInterestIndex          : 0.098630136986301369e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        vm.warp(startTimestamp + 360 days);

        // Interest has not accrued since last checkpoint given zero outstanding principal.
        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);
    }

    function test_repayPrincipal_multiple() external {
        uint256 firstAmount  = ISSUE_AMOUNT / 2;
        uint256 secondAmount = ISSUE_AMOUNT - firstAmount;

        uint256 startTimestamp = vm.getBlockTimestamp();

        // Make first principal repayment in 180 days so interest has accrued.
        vm.warp(startTimestamp + 180 days);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayPrincipal(address(facility), TOKEN_ID, firstAmount);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, firstAmount);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT + firstAmount);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT - firstAmount);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT - firstAmount,
            expectedMaxOutstandingInterest : 98_630.136986301369e18,
            expectedInterestIndex          : 0.098630136986301369e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        // Make second principal repayment in 180 days so interest has accrued.
        vm.warp(startTimestamp + 360 days);

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 147_945.2054794520535e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayPrincipal(address(facility), TOKEN_ID, secondAmount);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, secondAmount);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT + firstAmount + secondAmount);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT - firstAmount - secondAmount);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.197260273972602738e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : 0,
            expectedMaxOutstandingInterest : 147_945.2054794520535e18,
            expectedInterestIndex          : 0.197260273972602738e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 147_945.2054794520535e18);
    }

}

contract MainnetController_NFATHalo_RepayInterest_Tests is NFATHalo_PostIssue_TestBase {

    function test_repayInterest_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 1);
    }

    function test_repayInterest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 1);
    }

    function test_repayInterest_zeroAmount() external {
        vm.expectRevert("NFATHaloFacet/zero-amount");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 0);
    }

    function test_repayInterest_positionNotFound() external {
        vm.expectRevert("NFATHaloFacet/position-not-found");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), 99, 1);
    }

    function test_repayInterest_interestExceededBoundary() external {
        vm.warp(vm.getBlockTimestamp() + 180 days);

        vm.prank(allocator);
        vm.expectRevert("NFATHaloFacet/max-interest-exceeded");
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 98_630.136986301369e18 + 1);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 98_630.136986301369e18);
    }

    function test_repayInterest_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayInterestKey, 0, 0);

        vm.warp(vm.getBlockTimestamp() + 180 days);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 1);
    }

    function test_repayInterest_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayInterestKey, 50_000e18, 0);

        vm.warp(vm.getBlockTimestamp() + 180 days);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 50_000e18 + 1);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 50_000e18);
    }

    function test_repayInterest() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(repayInterestKey, 5_000_000e18, 0);

        uint256 startTimestamp = vm.getBlockTimestamp();

        vm.warp(startTimestamp + 180 days);

        assertEq(usds.balanceOf(address(facility)),                SUBSCRIBE_AMOUNT - ISSUE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)),                ISSUE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(repayInterestKey), 5_000_000e18);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayInterest(address(facility), TOKEN_ID, 98_630.136986301369e18);

        vm.record();

        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 98_630.136986301369e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(facility)),                    SUBSCRIBE_AMOUNT - ISSUE_AMOUNT + 98_630.136986301369e18);
        assertEq(usds.balanceOf(address(almProxy)),                    ISSUE_AMOUNT - 98_630.136986301369e18);
        assertEq(usds.allowance(address(almProxy), address(facility)), 0);
        assertEq(rateLimits.getCurrentRateLimit(repayInterestKey),     5_000_000e18 - 98_630.136986301369e18);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0.098630136986301369e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 0);
    }

    function test_repayInterest_multiple() external {
        uint256 startTimestamp = vm.getBlockTimestamp();

        // Make first interest repayment in 180 days so interest has accrued.
        vm.warp(startTimestamp + 180 days);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayInterest(address(facility), TOKEN_ID, 50_000e18);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 50_000e18);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT + 50_000e18);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT - 50_000e18);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 98_630.136986301369e18 - 50_000e18,
            expectedInterestIndex          : 0.098630136986301369e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18 - 50_000e18);

        // Make second interest repayment in 180 days so interest has accrued.
        vm.warp(startTimestamp + 360 days);

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 147_260.273972602738e18);

        vm.expectEmit(address(mainnetController));
        emit INFATHaloFacet.NFATHaloRepayInterest(address(facility), TOKEN_ID, 147_260.273972602738e18);

        vm.prank(allocator);
        mainnetController.nfatHalo_repayInterest(address(facility), TOKEN_ID, 147_260.273972602738e18);

        assertEq(usds.balanceOf(address(facility)), SUBSCRIBE_AMOUNT - ISSUE_AMOUNT + 50_000e18 + 147_260.273972602738e18);
        assertEq(usds.balanceOf(address(almProxy)), ISSUE_AMOUNT - 50_000e18 - 147_260.273972602738e18);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.197260273972602738e18,
            expectedLastUpdated   : vm.getBlockTimestamp()
        });

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0.197260273972602738e18
        });

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 0);
    }

}

contract MainnetController_NFATHalo_FacilityState_Tests is NFATHalo_TestBase {

    function test_getFacilityState() external {
        uint256 startTimestamp = vm.getBlockTimestamp();

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        vm.warp(startTimestamp + 180 days);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0,
            expectedLastUpdated   : startTimestamp
        });

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.nfatHalo_setMaxAnnualGrowthRate(address(facility), MAX_ANNUAL_GROWTH_RATE / 2);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : startTimestamp + 180 days
        });

        vm.warp(startTimestamp + 360 days);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.098630136986301369e18,
            expectedLastUpdated   : startTimestamp + 180 days
        });

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.nfatHalo_setMaxAnnualGrowthRate(address(facility), 0);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.147945205479452053e18,
            expectedLastUpdated   : startTimestamp + 360 days
        });

        vm.warp(startTimestamp + 540 days);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.147945205479452053e18,
            expectedLastUpdated   : startTimestamp + 360 days
        });

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.nfatHalo_setMaxAnnualGrowthRate(address(facility), 0);

        _assertFacilityState({
            facility              : address(facility),
            expectedInterestIndex : 0.147945205479452053e18,
            expectedLastUpdated   : startTimestamp + 540 days
        });
    }

}

contract MainnetController_NFATHalo_GetPosition_Tests is NFATHalo_PostIssue_TestBase {

    function test_getPosition() external {
        uint256 startTimestamp = vm.getBlockTimestamp();

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        vm.warp(startTimestamp + 180 days);

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT,
            expectedMaxOutstandingInterest : 0,
            expectedInterestIndex          : 0
        });

        vm.prank(allocator);
        mainnetController.nfatHalo_repayPrincipal(address(facility), TOKEN_ID, 1);

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT - 1,
            expectedMaxOutstandingInterest : 98_630.136986301369e18,
            expectedInterestIndex          : 0.098630136986301369e18
        });

        vm.warp(startTimestamp + 360 days);

        _assertPosition({
            facility                       : address(facility),
            tokenId                        : TOKEN_ID,
            expectedIssued                 : true,
            expectedOutstandingPrincipal   : ISSUE_AMOUNT - 1,
            expectedMaxOutstandingInterest : 98_630.136986301369e18,
            expectedInterestIndex          : 0.098630136986301369e18
        });
    }

}

contract MainnetController_NFATHalo_GetCurrentMaxOutstandingInterest_Tests is NFATHalo_PostIssue_TestBase {

    function test_getCurrentMaxOutstandingInterest_positionNotFound() external {
        vm.expectRevert("NFATHaloFacet/position-not-found");
        mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), 99);
    }

    function test_getCurrentMaxOutstandingInterest() external {
        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 0);

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(mainnetController.nfatHalo_getCurrentMaxOutstandingInterest(address(facility), TOKEN_ID), 98_630.136986301369e18);
    }

}
