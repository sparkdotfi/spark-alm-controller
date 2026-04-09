// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { IBasinFacet } from "../../src/facets/basin/IBasinFacet.sol";

import { MockBasin } from "../mocks/MockBasin.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

abstract contract Basin_TestBase is ForkTestBase {

    MockBasin internal mockBasin;

    function setUp() public virtual override {
        super.setUp();

        // Deploy mock for Basin (not yet deployed to mainnet)
        mockBasin = new MockBasin();
        vm.label(address(mockBasin), "MockBasin");

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_BASIN_DEPOSIT(),
                Ethereum.USDS,
                address(mockBasin)
            ),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_BASIN_WITHDRAW(),
                Ethereum.USDS,
                address(mockBasin)
            ),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        vm.stopPrank();
    }

}

contract MainnetController_Basin_Deposit_Tests is Basin_TestBase {

    function test_depositBasin_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_depositBasin_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_depositBasin_zeroMaxAmount() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_BASIN_DEPOSIT(),
            Ethereum.USDS,
            address(mockBasin)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_depositBasin_rateLimitBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 5_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 5_000_000e18);
    }

    function test_depositBasin() external {
        uint256 depositAmount = 1_000_000e18;

        deal(Ethereum.USDS, address(almProxy), depositAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  depositAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), 0);

        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), address(mockBasin)), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinDeposit({
            basin  : address(mockBasin),
            asset  : Ethereum.USDS,
            amount : depositAmount,
            shares : depositAmount
        });

        vm.prank(relayer);
        uint256 shares = mainnetController.depositBasin(
            address(mockBasin),
            Ethereum.USDS,
            depositAmount
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, depositAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  0);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), depositAmount);

        assertEq(IERC20Like(Ethereum.USDS).allowance(address(almProxy), address(mockBasin)), 0);
    }

    function test_depositBasin_customShares() external {
        uint256 depositAmount = 1_000_000e18;
        uint256 customShares  = 500_000e18;

        mockBasin.setDepositShares(customShares);
        deal(Ethereum.USDS, address(almProxy), depositAmount);

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinDeposit({
            basin  : address(mockBasin),
            asset  : Ethereum.USDS,
            amount : depositAmount,
            shares : customShares
        });

        vm.prank(relayer);
        uint256 shares = mainnetController.depositBasin(
            address(mockBasin),
            Ethereum.USDS,
            depositAmount
        );

        assertEq(shares, customShares);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  0);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), depositAmount);
    }

    function test_depositBasin_rateLimited() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_BASIN_DEPOSIT(),
            Ethereum.USDS,
            address(mockBasin)
        );

        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        vm.startPrank(relayer);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);

        skip(1 hours);

        deal(Ethereum.USDS, address(almProxy), 4_249_999.999999999999998400e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.999999999999998400e18);

        mainnetController.depositBasin(
            address(mockBasin),
            Ethereum.USDS,
            4_249_999.999999999999998400e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositBasin(address(mockBasin), Ethereum.USDS, 1);

        vm.stopPrank();
    }

}

contract MainnetController_Basin_Withdraw_Tests is Basin_TestBase {

    function test_withdrawBasin_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_withdrawBasin_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_withdrawBasin_zeroMaxAmount() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_BASIN_WITHDRAW(),
            Ethereum.USDS,
            address(mockBasin)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        // Withdraw executes before rate limit check, so need tokens in the mock
        deal(Ethereum.USDS, address(mockBasin), 1e18);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 1e18);
    }

    function test_withdrawBasin_rateLimitBoundary() external {
        deal(Ethereum.USDS, address(mockBasin), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 5_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 5_000_000e18);
    }

    function test_withdrawBasin() external {
        uint256 withdrawAmount = 1_000_000e18;

        deal(Ethereum.USDS, address(mockBasin), withdrawAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  0);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), withdrawAmount);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinWithdraw({
            basin           : address(mockBasin),
            asset           : Ethereum.USDS,
            assetsWithdrawn : withdrawAmount
        });

        vm.prank(relayer);
        uint256 assetsWithdrawn = mainnetController.withdrawBasin(
            address(mockBasin),
            Ethereum.USDS,
            withdrawAmount
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(assetsWithdrawn, withdrawAmount);

        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  withdrawAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), 0);
    }

    function test_withdrawBasin_customAmount() external {
        uint256 maxAmount    = 1_000_000e18;
        uint256 customAmount = 500_000e18;

        mockBasin.setWithdrawAmount(customAmount);
        deal(Ethereum.USDS, address(mockBasin), customAmount);

        vm.expectEmit(address(mainnetController));
        emit IBasinFacet.BasinWithdraw({
            basin           : address(mockBasin),
            asset           : Ethereum.USDS,
            assetsWithdrawn : customAmount
        });

        vm.prank(relayer);
        uint256 assetsWithdrawn = mainnetController.withdrawBasin(
            address(mockBasin),
            Ethereum.USDS,
            maxAmount
        );

        assertEq(assetsWithdrawn, customAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(almProxy)),  customAmount);
        assertEq(IERC20Like(Ethereum.USDS).balanceOf(address(mockBasin)), 0);
    }

    function test_withdrawBasin_rateLimited() external {
        bytes32 key = makeAddressAddressKey(
            mainnetController.LIMIT_BASIN_WITHDRAW(),
            Ethereum.USDS,
            address(mockBasin)
        );

        deal(Ethereum.USDS, address(mockBasin), 5_000_000e18);

        vm.startPrank(relayer);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e18);

        skip(1 hours);

        deal(Ethereum.USDS, address(mockBasin), 4_249_999.999999999999998400e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.999999999999998400e18);

        mainnetController.withdrawBasin(
            address(mockBasin),
            Ethereum.USDS,
            4_249_999.999999999999998400e18
        );

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        deal(Ethereum.USDS, address(mockBasin), 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawBasin(address(mockBasin), Ethereum.USDS, 1);

        vm.stopPrank();
    }

}
