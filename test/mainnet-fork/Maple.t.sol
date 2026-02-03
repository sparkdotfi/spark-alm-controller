// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

import {
    IMapleTokenExtendedLike,
    IPermissionManagerLike,
    IPoolManagerLike,
    IWithdrawalManagerLike
} from "../interfaces/Maple.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract Maple_TestBase is ForkTestBase {

    IMapleTokenExtendedLike internal constant syrup =
        IMapleTokenExtendedLike(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);

    IPermissionManagerLike internal constant permissionManager =
        IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    uint256 internal syrupConvertedAssets;
    uint256 internal syrupConvertedShares;

    uint256 internal usdcBalanceOfSyrup;

    uint256 internal syrupTotalAssets;
    uint256 internal syrupTotalSupply;

    bytes32 internal depositKey;
    bytes32 internal redeemKey;

    function setUp() override public {
        super.setUp();

        depositKey = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), address(syrup));
        redeemKey  = makeAddressKey(mainnetController.LIMIT_MAPLE_REDEEM(), address(syrup));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(redeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        mainnetController.setMaxExchangeRate(address(syrup), syrup.convertToShares(1e18), 2e18);
        vm.stopPrank();

        // Maple onboarding process
        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(almProxy);
        booleans[0] = true;

        vm.startPrank(permissionManager.admin());
        permissionManager.setLenderAllowlist(
            syrup.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();

        syrupConvertedAssets = syrup.convertToAssets(1_000_000e6);
        syrupConvertedShares = syrup.convertToShares(1_000_000e6);

        syrupTotalAssets = syrup.totalAssets();
        syrupTotalSupply = syrup.totalSupply();

        usdcBalanceOfSyrup = usdc.balanceOf(address(syrup));

        assertEq(syrupConvertedAssets, 1_066_100.425881e6);
        assertEq(syrupConvertedShares, 937_997.936895e6);

        assertEq(syrupTotalAssets, 59_578_045.544596e6);
        assertEq(syrupTotalSupply, 55_884_083.805100e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21570000;  // Jan 7, 2024
    }

}

contract MainnetController_ERC4626_Maple_Deposit_Tests is Maple_TestBase {

    function test_depositERC4626_maple_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_rateLimitBoundary() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6 + 1, 0);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_exchangeRateTooHigh() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(syrup), syrup.convertToShares(1_000_000e6), 1_000_000e6 - 1);
        vm.stopPrank();

        vm.expectRevert("ERC4626Lib/exchange-rate-too-high");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(syrup), syrup.convertToShares(1_000_000e6), 1_000_000e6);
        vm.stopPrank();

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_zeroExchangeRate() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(syrup), 0, 0);

        vm.expectRevert("ERC4626Lib/exchange-rate-too-high");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_minSharesOutNotMetBoundary() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        uint256 overBoundaryShares = syrup.convertToShares(1_000_000e6 + 1);
        uint256 atBoundaryShares   = syrup.convertToShares(1_000_000e6);

        vm.expectRevert("ERC4626Lib/min-shares-out-not-met");
        vm.startPrank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6, overBoundaryShares);

        mainnetController.depositERC4626(address(syrup), 1_000_000e6, atBoundaryShares);
    }

    function test_depositERC4626_maple() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             usdcBalanceOfSyrup);

        assertEq(usdc.allowance(address(almProxy), address(syrup)),  0);

        assertEq(syrup.totalSupply(),                syrupTotalSupply);
        assertEq(syrup.totalAssets(),                syrupTotalAssets);
        assertEq(syrup.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(
            address(syrup),
            1_000_000e6,
            syrupConvertedShares
        );

        assertEq(shares, syrupConvertedShares);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             usdcBalanceOfSyrup + 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(syrup)), 0);

        assertEq(syrup.totalSupply(),                syrupTotalSupply + shares);
        assertEq(syrup.totalAssets(),                syrupTotalAssets + 1_000_000e6);
        assertEq(syrup.balanceOf(address(almProxy)), shares);
    }

}

contract MainnetController_Maple_RequestRedemption_Tests is Maple_TestBase {

    function test_requestMapleRedemption_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_requestMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_requestMapleRedemption_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_requestMapleRedemption_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 5_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 5_000_000e6);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 5_000_000e6, 0);

        uint256 overBoundaryShares = syrup.convertToShares(1_000_000e6 + 2);  // Rounding
        uint256 atBoundaryShares   = syrup.convertToShares(1_000_000e6 + 1);  // Rounding

        assertEq(syrup.convertToAssets(overBoundaryShares), 1_000_000e6 + 1);
        assertEq(syrup.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), overBoundaryShares);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), atBoundaryShares);
    }

    function test_requestMapleRedemption() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);

        address withdrawalManager   = IPoolManagerLike(syrup.manager()).withdrawalManager();
        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    0);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);
    }
}

contract MainnetController_Maple_CancelRedemption_Tests is Maple_TestBase {

    function test_cancelMapleRedemption_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.cancelMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_cancelMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_cancelMapleRedemption_invalidMapleToken() external {
        vm.expectRevert("MapleLib/invalid-action");
        vm.prank(relayer);
        mainnetController.cancelMapleRedemption(makeAddr("fake-syrup"), 1_000_000e6);
    }

    function test_cancelMapleRedemption() external {
        address withdrawalManager   = IPoolManagerLike(syrup.manager()).withdrawalManager();
        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);

        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);

        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),          0);

        vm.record();

        mainnetController.cancelMapleRedemption(address(syrup), proxyShares);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),          proxyShares);

        vm.stopPrank();
    }

}

contract MainnetController_Maple_E2ETests is Maple_TestBase {

    function test_e2e_mapleDepositAndRedeem() external {
        // Increase withdraw rate limit so interest can be accrued
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 2_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        // --- Step 1: Deposit USDC into Maple ---

        assertEq(usdc.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             usdcBalanceOfSyrup);

        assertEq(usdc.allowance(address(almProxy), address(syrup)),  0);

        assertEq(syrup.totalSupply(),                syrupTotalSupply);
        assertEq(syrup.totalAssets(),                syrupTotalAssets);
        assertEq(syrup.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6, 0);

        assertEq(proxyShares, syrupConvertedShares);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             usdcBalanceOfSyrup + 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(syrup)), 0);

        assertEq(syrup.totalSupply(),                syrupTotalSupply + proxyShares);
        assertEq(syrup.totalAssets(),                syrupTotalAssets + 1_000_000e6);
        assertEq(syrup.balanceOf(address(almProxy)), syrupConvertedShares);

        // --- Step 2: Request Redeem ---

        skip(1 days);  // Warp to accrue interest

        address withdrawalManager   = IPoolManagerLike(syrup.manager()).withdrawalManager();
        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    0);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        // --- Step 3: Fulfill Redeem (done by Maple) ---

        skip(1 days);  // Warp to accrue more interest

        uint256 totalAssets    = syrup.totalAssets();
        uint256 withdrawAssets = syrup.convertToAssets(proxyShares);
        uint256 usdcPoolBal    = usdc.balanceOf(address(syrup));

        assertGt(totalAssets, syrupTotalAssets + 1_000_000e6);  // Interest accrued

        assertEq(withdrawAssets, 1_000_423.216342e6);  // Interest accrued

        assertEq(syrup.totalSupply(),                         syrupTotalSupply + proxyShares);
        assertEq(syrup.totalAssets(),                         totalAssets);
        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares + proxyShares);

        assertEq(usdc.balanceOf(address(syrup)),    usdcPoolBal);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        // NOTE: `proxyShares` can be used in this case because almProxy is the only account using the
        //       `withdrawalManager` at this fork block. Usually `processRedemptions` requires
        //       `maxSharesToProcess` to include the shares of all accounts ahead of almProxy in
        //       queue plus almProxy's shares.
        vm.prank(IPoolManagerLike(syrup.manager()).poolDelegate());
        IWithdrawalManagerLike(withdrawalManager).processRedemptions(proxyShares);

        assertEq(syrup.totalSupply(),                         syrupTotalSupply);
        assertEq(syrup.totalAssets(),                         totalAssets - withdrawAssets);
        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares);

        assertEq(usdc.balanceOf(address(syrup)),    usdcPoolBal - withdrawAssets);
        assertEq(usdc.balanceOf(address(almProxy)), withdrawAssets);
    }
}
