// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import {
    IMapleTokenExtendedLike,
    IPermissionManagerLike,
    IPoolManagerLike,
    IWithdrawalManagerLike
} from "../interfaces/Maple.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

}

abstract contract Maple_TestBase is ForkTestBase {

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    IMapleTokenExtendedLike internal constant SYRUP = IMapleTokenExtendedLike(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);

    IPermissionManagerLike internal constant PERMISSION_MANAGER
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    uint256 internal syrupConvertedAssets;
    uint256 internal syrupConvertedShares;

    uint256 internal syrupUSDCBalance;

    uint256 internal syrupTotalAssets;
    uint256 internal syrupTotalSupply;

    bytes32 internal depositKey;
    bytes32 internal redeemKey;

    function setUp() public override {
        super.setUp();

        depositKey = makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), address(SYRUP));
        redeemKey  = makeAddressKey(mainnetController.LIMIT_MAPLE_REDEEM(), address(SYRUP));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(redeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        mainnetController.setMaxExchangeRate(address(SYRUP), SYRUP.convertToShares(1e18), 2e18);
        vm.stopPrank();

        // Maple onboarding process
        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(almProxy);
        booleans[0] = true;

        vm.startPrank(PERMISSION_MANAGER.admin());
        PERMISSION_MANAGER.setLenderAllowlist(
            SYRUP.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();

        syrupConvertedAssets = SYRUP.convertToAssets(1_000_000e6);
        syrupConvertedShares = SYRUP.convertToShares(1_000_000e6);

        syrupTotalAssets = SYRUP.totalAssets();
        syrupTotalSupply = SYRUP.totalSupply();

        syrupUSDCBalance = USDC.balanceOf(address(SYRUP));

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
            RELAYER_ROLE
        ));
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_rateLimitBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6 + 1, 0);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_exchangeRateTooHigh() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(SYRUP), SYRUP.convertToShares(1_000_000e6), 1_000_000e6 - 1);
        vm.stopPrank();

        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(SYRUP), SYRUP.convertToShares(1_000_000e6), 1_000_000e6);
        vm.stopPrank();

        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_zeroExchangeRate() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(SYRUP), 0, 0);

        vm.expectRevert("ERC4626Facet/exchange-rate-too-high");
        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);
    }

    function test_depositERC4626_maple_minSharesOutNotMetBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        uint256 overBoundaryShares = SYRUP.convertToShares(1_000_000e6 + 1);
        uint256 atBoundaryShares   = SYRUP.convertToShares(1_000_000e6);

        vm.expectRevert("ERC4626Facet/min-shares-out-not-met");
        vm.startPrank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, overBoundaryShares);

        mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, atBoundaryShares);
    }

    function test_depositERC4626_maple() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(address(SYRUP)),             syrupUSDCBalance);

        assertEq(USDC.allowance(address(almProxy), address(SYRUP)),  0);

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply);
        assertEq(SYRUP.totalAssets(),                syrupTotalAssets);
        assertEq(SYRUP.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(
            address(SYRUP),
            1_000_000e6,
            syrupConvertedShares
        );

        assertEq(shares, syrupConvertedShares);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(address(SYRUP)),             syrupUSDCBalance + 1_000_000e6);

        assertEq(USDC.allowance(address(almProxy), address(SYRUP)), 0);

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply + shares);
        assertEq(SYRUP.totalAssets(),                syrupTotalAssets + 1_000_000e6);
        assertEq(SYRUP.balanceOf(address(almProxy)), shares);
    }

}

contract MainnetController_Maple_RequestRedemption_Tests is Maple_TestBase {

    function test_requestMapleRedemption_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.requestMapleRedemption(address(SYRUP), 1_000_000e6);
    }

    function test_requestMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.requestMapleRedemption(address(SYRUP), 1_000_000e6);
    }

    function test_requestMapleRedemption_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(SYRUP), 1_000_000e6);
    }

    function test_requestMapleRedemption_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 5_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Ethereum.USDC, address(almProxy), 5_000_000e6);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(SYRUP), 5_000_000e6, 0);

        uint256 overBoundaryShares = SYRUP.convertToShares(1_000_000e6 + 2);  // Rounding
        uint256 atBoundaryShares   = SYRUP.convertToShares(1_000_000e6 + 1);  // Rounding

        assertEq(SYRUP.convertToAssets(overBoundaryShares), 1_000_000e6 + 1);
        assertEq(SYRUP.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(SYRUP), overBoundaryShares);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(SYRUP), atBoundaryShares);
    }

    function test_requestMapleRedemption() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);

        address withdrawalManager   = IPoolManagerLike(SYRUP.manager()).withdrawalManager();
        uint256 totalEscrowedShares = SYRUP.balanceOf(withdrawalManager);

        assertEq(SYRUP.balanceOf(withdrawalManager),                    totalEscrowedShares);
        assertEq(SYRUP.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(SYRUP.allowance(address(almProxy), withdrawalManager), 0);

        vm.record();

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(SYRUP), proxyShares);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(SYRUP.balanceOf(withdrawalManager),                    totalEscrowedShares + proxyShares);
        assertEq(SYRUP.balanceOf(address(almProxy)),                    0);
        assertEq(SYRUP.allowance(address(almProxy), withdrawalManager), 0);
    }
}

contract MainnetController_Maple_CancelRedemption_Tests is Maple_TestBase {

    function test_cancelMapleRedemption_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.cancelMapleRedemption(address(SYRUP), 1_000_000e6);
    }

    function test_cancelMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.cancelMapleRedemption(address(SYRUP), 1_000_000e6);
    }

    function test_cancelMapleRedemption_invalidMapleToken() external {
        vm.expectRevert("MapleFacet/invalid-action");
        vm.prank(relayer);
        mainnetController.cancelMapleRedemption(makeAddr("fake-SYRUP"), 1_000_000e6);
    }

    function test_cancelMapleRedemption() external {
        address withdrawalManager   = IPoolManagerLike(SYRUP.manager()).withdrawalManager();
        uint256 totalEscrowedShares = SYRUP.balanceOf(withdrawalManager);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);

        uint256 proxyShares = mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);

        mainnetController.requestMapleRedemption(address(SYRUP), proxyShares);

        assertEq(SYRUP.balanceOf(withdrawalManager), totalEscrowedShares + proxyShares);
        assertEq(SYRUP.balanceOf(address(almProxy)), 0);

        vm.record();

        mainnetController.cancelMapleRedemption(address(SYRUP), proxyShares);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(SYRUP.balanceOf(withdrawalManager), totalEscrowedShares);
        assertEq(SYRUP.balanceOf(address(almProxy)), proxyShares);

        vm.stopPrank();
    }

}

contract MainnetController_Maple_E2ETests is Maple_TestBase {

    function test_e2e_mapleDepositAndRedeem() external {
        // Increase withdraw rate limit so interest can be accrued
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 2_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        // --- Step 1: Deposit USDC into Maple ---

        assertEq(USDC.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(address(SYRUP)),             syrupUSDCBalance);

        assertEq(USDC.allowance(address(almProxy), address(SYRUP)),  0);

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply);
        assertEq(SYRUP.totalAssets(),                syrupTotalAssets);
        assertEq(SYRUP.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(SYRUP), 1_000_000e6, 0);

        assertEq(proxyShares, syrupConvertedShares);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(address(SYRUP)),             syrupUSDCBalance + 1_000_000e6);

        assertEq(USDC.allowance(address(almProxy), address(SYRUP)), 0);

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply + proxyShares);
        assertEq(SYRUP.totalAssets(),                syrupTotalAssets + 1_000_000e6);
        assertEq(SYRUP.balanceOf(address(almProxy)), syrupConvertedShares);

        // --- Step 2: Request Redeem ---

        skip(1 days);  // Warp to accrue interest

        address withdrawalManager   = IPoolManagerLike(SYRUP.manager()).withdrawalManager();
        uint256 totalEscrowedShares = SYRUP.balanceOf(withdrawalManager);

        assertEq(SYRUP.balanceOf(withdrawalManager),                    totalEscrowedShares);
        assertEq(SYRUP.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(SYRUP.allowance(address(almProxy), withdrawalManager), 0);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(SYRUP), proxyShares);

        assertEq(SYRUP.balanceOf(withdrawalManager),                    totalEscrowedShares + proxyShares);
        assertEq(SYRUP.balanceOf(address(almProxy)),                    0);
        assertEq(SYRUP.allowance(address(almProxy), withdrawalManager), 0);

        // --- Step 3: Fulfill Redeem (done by Maple) ---

        skip(1 days);  // Warp to accrue more interest

        uint256 totalAssets    = SYRUP.totalAssets();
        uint256 withdrawAssets = SYRUP.convertToAssets(proxyShares);
        uint256 usdcPoolBal    = USDC.balanceOf(address(SYRUP));

        assertGt(totalAssets, syrupTotalAssets + 1_000_000e6);  // Interest accrued

        assertEq(withdrawAssets, 1_000_423.216342e6);  // Interest accrued

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply + proxyShares);
        assertEq(SYRUP.totalAssets(),                totalAssets);
        assertEq(SYRUP.balanceOf(withdrawalManager), totalEscrowedShares + proxyShares);

        assertEq(USDC.balanceOf(address(SYRUP)),    usdcPoolBal);
        assertEq(USDC.balanceOf(address(almProxy)), 0);

        // NOTE: `proxyShares` can be used in this case because almProxy is the only account using the
        //       `withdrawalManager` at this fork block. Usually `processRedemptions` requires
        //       `maxSharesToProcess` to include the shares of all accounts ahead of almProxy in
        //       queue plus almProxy's shares.
        vm.prank(IPoolManagerLike(SYRUP.manager()).poolDelegate());
        IWithdrawalManagerLike(withdrawalManager).processRedemptions(proxyShares);

        assertEq(SYRUP.totalSupply(),                syrupTotalSupply);
        assertEq(SYRUP.totalAssets(),                totalAssets - withdrawAssets);
        assertEq(SYRUP.balanceOf(withdrawalManager), totalEscrowedShares);

        assertEq(USDC.balanceOf(address(SYRUP)),    usdcPoolBal - withdrawAssets);
        assertEq(USDC.balanceOf(address(almProxy)), withdrawAssets);
    }
}
