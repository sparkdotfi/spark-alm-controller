// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { NFATFacility } from "../../lib/nfat/src/NFATFacility.sol";

import { makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract NFATPrime_TestBase is ForkTestBase {

    NFATFacility internal nfatFacility;
    address      internal nfatRecipient;

    bytes32 internal subscribeKey;
    bytes32 internal collectKey;

    uint256 internal constant SUBSCRIBE_AMOUNT = 1_000_000e18;

    function setUp() public virtual override {
        super.setUp();

        nfatRecipient = makeAddr("nfatRecipient");

        nfatFacility = new NFATFacility(Ethereum.USDS, "Test NFAT", "TNFAT");
        nfatFacility.file("recipient", nfatRecipient);
        nfatFacility.kiss(address(this));  // Make test contract an operator (bud)

        subscribeKey = makeAddressKey(mainnetController.LIMIT_NFAT_SUBSCRIBE(), address(nfatFacility));
        collectKey   = makeAddressKey(mainnetController.LIMIT_NFAT_COLLECT(),   address(nfatFacility));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(collectKey,   1_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);
    }

}

contract MainnetController_NFATPrime_Subscribe_Tests is NFATPrime_TestBase {

    function test_subscribeNFAT_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribeNFAT_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribeNFAT_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.subscribeNFAT(makeAddr("fake-facility"), SUBSCRIBE_AMOUNT, "");
    }

    function test_subscribeNFAT_rateLimitBoundary() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.subscribeNFAT(address(nfatFacility), 5_000_000e18 + 1, "");

        mainnetController.subscribeNFAT(address(nfatFacility), 5_000_000e18, "");

        vm.stopPrank();
    }

    function test_subscribeNFAT() external {
        assertEq(usds.balanceOf(address(almProxy)),                        5_000_000e18);
        assertEq(usds.allowance(address(almProxy), address(nfatFacility)), 0);
        assertEq(nfatFacility.deposits(address(almProxy)),                 0);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),             5_000_000e18);

        vm.record();

        vm.prank(relayer);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)),                        5_000_000e18 - SUBSCRIBE_AMOUNT);
        assertEq(usds.allowance(address(almProxy), address(nfatFacility)), 0);
        assertEq(nfatFacility.deposits(address(almProxy)),                 SUBSCRIBE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),             5_000_000e18 - SUBSCRIBE_AMOUNT);
    }

    function test_subscribeNFAT_withData() external {
        bytes memory data = abi.encode("agreement-id-123");

        vm.expectEmit(address(nfatFacility));
        emit NFATFacility.Subscribe(address(almProxy), SUBSCRIBE_AMOUNT, data);

        vm.prank(relayer);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, data);

        assertEq(nfatFacility.deposits(address(almProxy)), SUBSCRIBE_AMOUNT);
    }

}

contract MainnetController_NFATPrime_Withdraw_Tests is NFATPrime_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(relayer);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");
    }

    function test_withdrawNFAT_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.withdrawNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT);
    }

    function test_withdrawNFAT_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.withdrawNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT);
    }

    function test_withdrawNFAT_noCode() external {
        vm.expectRevert(abi.encodeWithSignature("AddressEmptyCode(address)", makeAddr("fake-facility")));
        vm.prank(relayer);
        mainnetController.withdrawNFAT(makeAddr("fake-facility"), SUBSCRIBE_AMOUNT);
    }

    function test_withdrawNFAT_notApproved() external {
        // Deploy a facility with code but no rate limit registered — doCall succeeds,
        // then triggerRateLimitIncrease reverts because maxAmount == 0.
        NFATFacility nfatFacility2 = new NFATFacility(Ethereum.USDS, "Test NFAT 2", "TNFAT2");

        // Subscribe directly as almProxy to give it deposits to withdraw against.
        vm.startPrank(address(almProxy));
        usds.approve(address(nfatFacility2), SUBSCRIBE_AMOUNT);
        nfatFacility2.subscribe(SUBSCRIBE_AMOUNT, "");
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.withdrawNFAT(address(nfatFacility2), SUBSCRIBE_AMOUNT);
    }

    function test_withdrawNFAT() external {
        assertEq(usds.balanceOf(address(almProxy)),        5_000_000e18 - SUBSCRIBE_AMOUNT);
        assertEq(nfatFacility.deposits(address(almProxy)), SUBSCRIBE_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey), 5_000_000e18 - SUBSCRIBE_AMOUNT);

        vm.record();

        vm.prank(relayer);
        mainnetController.withdrawNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)),        5_000_000e18);
        assertEq(nfatFacility.deposits(address(almProxy)), 0);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey), 5_000_000e18);
    }

}

contract MainnetController_NFATPrime_Collect_Tests is NFATPrime_TestBase {

    uint256 internal constant TOKEN_ID     = 1;
    uint256 internal constant REPAY_AMOUNT = 2_000_000e18;

    function setUp() public override {
        super.setUp();

        // Subscribe and issue so the proxy holds an NFT
        vm.prank(relayer);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");

        nfatFacility.issue(address(almProxy), TOKEN_ID, SUBSCRIBE_AMOUNT);

        // Fund the collectable balance via an external repayer
        deal(Ethereum.USDS, address(this), REPAY_AMOUNT);
        usds.approve(address(nfatFacility), REPAY_AMOUNT);
        nfatFacility.repay(TOKEN_ID, REPAY_AMOUNT);
    }

    function test_collectNFAT_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.collectNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);
    }

    function test_collectNFAT_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.collectNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);
    }

    function test_collectNFAT_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.collectNFAT(makeAddr("fake-facility"), TOKEN_ID, 1_000_000e18);
    }

    function test_collectNFAT_rateLimitBoundary() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.collectNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18 + 1);

        mainnetController.collectNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);

        vm.stopPrank();
    }

    function test_collectNFAT() external {
        uint256 collectAmount = 1_000_000e18;

        assertEq(usds.balanceOf(address(almProxy)),             5_000_000e18 - SUBSCRIBE_AMOUNT);
        assertEq(nfatFacility.collectable(TOKEN_ID),            REPAY_AMOUNT);
        assertEq(rateLimits.getCurrentRateLimit(collectKey),    1_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),  5_000_000e18 - SUBSCRIBE_AMOUNT);

        vm.record();

        vm.prank(relayer);
        mainnetController.collectNFAT(address(nfatFacility), TOKEN_ID, collectAmount);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)),             5_000_000e18 - SUBSCRIBE_AMOUNT + collectAmount);
        assertEq(nfatFacility.collectable(TOKEN_ID),            REPAY_AMOUNT - collectAmount);
        assertEq(rateLimits.getCurrentRateLimit(collectKey),    0);
        assertEq(rateLimits.getCurrentRateLimit(subscribeKey),  5_000_000e18 - SUBSCRIBE_AMOUNT + collectAmount);
    }

}
