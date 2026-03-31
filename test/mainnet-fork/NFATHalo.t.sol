// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { NFATFacility } from "../../lib/nfat/src/NFATFacility.sol";

import { makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract NFATHalo_TestBase is ForkTestBase {

    NFATFacility internal nfatFacility;
    address      internal nfatRecipient;

    bytes32 internal subscribeKey;
    bytes32 internal repayKey;

    uint256 internal constant SUBSCRIBE_AMOUNT = 1_000_000e18;

    function setUp() public virtual override {
        super.setUp();

        nfatRecipient = makeAddr("nfatRecipient");

        nfatFacility = new NFATFacility(Ethereum.USDS, "Test NFAT", "TNFAT");
        nfatFacility.file("recipient", nfatRecipient);
        nfatFacility.kiss(address(this));  // Make test contract an operator (bud)

        subscribeKey = makeAddressKey(mainnetController.LIMIT_NFAT_SUBSCRIBE(), address(nfatFacility));
        repayKey     = makeAddressKey(mainnetController.LIMIT_NFAT_REPAY(),     address(nfatFacility));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(subscribeKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(repayKey,     1_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);
    }

}

contract MainnetController_NFATHalo_Repay_Tests is NFATHalo_TestBase {

    uint256 internal constant TOKEN_ID = 1;

    function setUp() public override {
        super.setUp();

        // Subscribe and issue so there is a valid token to repay against
        vm.prank(relayer);
        mainnetController.subscribeNFAT(address(nfatFacility), SUBSCRIBE_AMOUNT, "");

        nfatFacility.issue(address(almProxy), TOKEN_ID, SUBSCRIBE_AMOUNT);
    }

    function test_repayNFAT_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.repayNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);
    }

    function test_repayNFAT_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.repayNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);
    }

    function test_repayNFAT_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.repayNFAT(makeAddr("fake-facility"), TOKEN_ID, 1_000_000e18);
    }

    function test_repayNFAT_rateLimitBoundary() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.repayNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18 + 1);

        mainnetController.repayNFAT(address(nfatFacility), TOKEN_ID, 1_000_000e18);

        vm.stopPrank();
    }

    function test_repayNFAT() external {
        uint256 repayAmount = 1_000_000e18;

        assertEq(usds.balanceOf(address(almProxy)),          5_000_000e18 - SUBSCRIBE_AMOUNT);
        assertEq(usds.allowance(address(almProxy), address(nfatFacility)), 0);
        assertEq(nfatFacility.collectable(TOKEN_ID),         0);
        assertEq(rateLimits.getCurrentRateLimit(repayKey),   1_000_000e18);

        vm.record();

        vm.prank(relayer);
        mainnetController.repayNFAT(address(nfatFacility), TOKEN_ID, repayAmount);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.balanceOf(address(almProxy)),          5_000_000e18 - SUBSCRIBE_AMOUNT - repayAmount);
        assertEq(usds.allowance(address(almProxy), address(nfatFacility)), 0);
        assertEq(nfatFacility.collectable(TOKEN_ID),         repayAmount);
        assertEq(rateLimits.getCurrentRateLimit(repayKey),   0);
    }

}
