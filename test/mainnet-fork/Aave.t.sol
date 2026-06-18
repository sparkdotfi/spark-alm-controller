// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { DataTypes } from "../../lib/aave-v3-origin/src/core/contracts/protocol/libraries/types/DataTypes.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum }  from "../../lib/spark-address-registry/src/Ethereum.sol";
import { SparkLend } from "../../lib/spark-address-registry/src/SparkLend.sol";

import { IAaveFacet } from "../../src/facets/aave/IAaveFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IAavePoolLike {

    function flashLoan(
        address            receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address            onBehalfOf,
        bytes     calldata params,
        uint16             referralCode
    ) external;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external;

    function getReserveData(address asset) external view returns (DataTypes.ReserveDataLegacy memory);

}

interface IERC20Like {

    function approve(address spender, uint256 amount) external;

    function transfer(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IPoolConfiguratorLike {

    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external;

}

abstract contract AaveV3_TestBase is ForkTestBase {

    address internal constant ATOKEN_USDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address internal constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant POOL        = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    IERC20Like internal constant AUSDS = IERC20Like(ATOKEN_USDS);
    IERC20Like internal constant AUSDC = IERC20Like(ATOKEN_USDC);

    uint256 internal startingAUSDSBalance;
    uint256 internal startingAUSDCBalance;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDS, POOL, Ethereum.USDS),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDC, POOL, Ethereum.USDC),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDS, POOL),
            10_000_000e18,
            uint256(5_000_000e18) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDC, POOL),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        mainnetController.aave_setMaxSlippage(ATOKEN_USDS, 1e18 - 1e4);  // Rounding slippage
        mainnetController.aave_setMaxSlippage(ATOKEN_USDC, 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();

        startingAUSDCBalance = usdc.balanceOf(ATOKEN_USDC);
        startingAUSDSBalance = usds.balanceOf(ATOKEN_USDS);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used

contract MainnetController_AaveV3_Deposit_Tests is AaveV3_TestBase {

    function test_depositAave_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aave_deposit(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aave_deposit(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDS, POOL, Ethereum.USDS),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 1e18);
    }

    function test_depositAave_zeroMaxSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(ATOKEN_USDS, 0);

        vm.expectRevert("AaveFacet/max-slippage-not-set");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 1e18);
    }

    function test_depositAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 25_000_000e18 + 1);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 25_000_000e18);
    }

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 25_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 25_000_000e6);
    }

    function test_depositAave_usdsSlippageBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        // Positive slippage because of no rounding error
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(ATOKEN_USDS, 1e18 + 1);

        vm.expectRevert("AaveFacet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 5_000_000e18);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(ATOKEN_USDS, 1e18);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 5_000_000e18);
    }

    function test_depositAave_usdcSlippageBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 5_000_000e6);

        // Positive slippage because of no rounding error
        // 0.2e6 * 5_000_000e6 / 1e18 = 1
        // (0.2e6 - 1) * 5_000_000e6 / 1e18 = 0
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(ATOKEN_USDC, 1e18 + 0.2e6);

        vm.expectRevert("AaveFacet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 5_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(ATOKEN_USDC, 1e18 + 0.2e6 - 1);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 5_000_000e6);
    }

    function test_depositAave_usds() external {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        bytes32 depositKey = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDS, POOL, Ethereum.USDS);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(AUSDS.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  1_000_000e18);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit(ATOKEN_USDS, 1_000_000e18);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey), startingDepositRateLimit - 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(AUSDS.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 1_000_000e18);
    }

    function test_depositAave_usdc() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(AUSDC.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit(ATOKEN_USDC, 1_000_000e6);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(AUSDC.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 1_000_000e6);
    }

}

contract MainnetController_AaveV3_Withdraw_Tests is AaveV3_TestBase {

    function test_withdrawAave_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.aave_withdraw(ATOKEN_USDS, 1_000_000e18);
    }

    function test_withdrawAave_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.aave_withdraw(ATOKEN_USDS, 1_000_000e18);
    }

    function test_withdrawAave_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDC, POOL),
            0,
            0
        );
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 1_000_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.aave_withdraw(ATOKEN_USDC, 1_000_000e6);
    }

    function test_withdrawAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 15_000_000e18);

        vm.startPrank(allocator);

        mainnetController.aave_deposit(ATOKEN_USDS, 15_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aave_withdraw(ATOKEN_USDS, 10_000_000e18 + 1);

        mainnetController.aave_withdraw(ATOKEN_USDS, 10_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 15_000_000e6);

        vm.startPrank(allocator);

        mainnetController.aave_deposit(ATOKEN_USDC, 15_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.aave_withdraw(ATOKEN_USDC, 10_000_000e6 + 1);

        mainnetController.aave_withdraw(ATOKEN_USDC, 10_000_000e6);

        vm.stopPrank();
    }

    function test_withdrawAave_usds() external {
        bytes32 depositKey  = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDS, POOL, Ethereum.USDS);
        bytes32 withdrawKey = mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDS, POOL);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit({ aToken: ATOKEN_USDS, amount: 1_000_000e18 });

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = AUSDS.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        assertEq(AUSDS.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 1_000_000e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        vm.record();

        // Partial withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw(ATOKEN_USDS, 400_000e18);

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDS, 400_000e18), 400_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(AUSDS.balanceOf(address(almProxy)), aTokenBalance - 400_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  400_000e18);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 600_000e18);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e18);

        // Withdraw all
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw(ATOKEN_USDS, aTokenBalance - 400_000e18);

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDS, type(uint256).max), aTokenBalance - 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18 - aTokenBalance);

        assertEq(AUSDS.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 1_000_000e18 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usds.balanceOf(ATOKEN_USDS), startingAUSDSBalance);
    }

    function test_withdrawAave_usds_unlimitedRateLimit() external {
        bytes32 depositKey  = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDS, POOL, Ethereum.USDS);
        bytes32 withdrawKey = mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDS, POOL);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit({ aToken: ATOKEN_USDS, amount: 1_000_000e18 });

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = AUSDS.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(AUSDS.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 1_000_000e18);

        // Full withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw({ aToken: ATOKEN_USDS, amountWithdrawn: aTokenBalance });

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDS, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(AUSDS.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usds.balanceOf(ATOKEN_USDS),        startingAUSDSBalance + 1_000_000e18 - aTokenBalance);
    }

    function test_withdrawAave_usdc() external {
        bytes32 depositKey  = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDC, POOL, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDC, POOL);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit({ aToken: ATOKEN_USDC, amount: 1_000_000e6 });

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = AUSDC.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        assertEq(AUSDC.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 1_000_000e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        // Partial withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw(ATOKEN_USDC, 400_000e6);

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(AUSDC.balanceOf(address(almProxy)), aTokenBalance - 400_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  400_000e6);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 600_000e6);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e6);

        // Withdraw all
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw(ATOKEN_USDC, aTokenBalance - 400_000e6);

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDC, type(uint256).max), aTokenBalance - 400_000e6);

        assertEq(AUSDC.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 1_000_000e6 - aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usdc.balanceOf(ATOKEN_USDC), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_zeroDepositRateLimit() external {
        bytes32 depositKey  = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDC, POOL, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDC, POOL);

        // NOTE: Using lower amount to not hit rate limit
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        // Partial withdraw
        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  24_400_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e6);

        // Zero deposit rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 0);

        // Partial withdraw
        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  0);  // stays at 0
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_200_000e6);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() external {
        bytes32 depositKey  = mainnetController.aave_getDepositRateLimitKey(ATOKEN_USDC, POOL, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.aave_getWithdrawRateLimitKey(ATOKEN_USDC, POOL);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveDeposit({ aToken: ATOKEN_USDC, amount: 1_000_000e6 });

        vm.prank(allocator);
        mainnetController.aave_deposit(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = AUSDC.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(AUSDC.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 1_000_000e6);

        // Full withdraw
        vm.expectEmit(address(mainnetController));
        emit IAaveFacet.AaveWithdraw({ aToken: ATOKEN_USDC, amountWithdrawn: aTokenBalance });

        vm.prank(allocator);
        assertEq(mainnetController.aave_withdraw(ATOKEN_USDC, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(AUSDC.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usdc.balanceOf(ATOKEN_USDC),        startingAUSDCBalance + 1_000_000e6 - aTokenBalance);
    }

}

abstract contract AaveV3_Attack_TestBase is ForkTestBase {

    IAavePoolLike internal constant POOL = IAavePoolLike(SparkLend.POOL);

    IERC20Like internal constant PYUSD_SPTOKEN = IERC20Like(SparkLend.PYUSD_SPTOKEN);
    IERC20Like internal constant PYUSD         = IERC20Like(Ethereum.PYUSD);

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            mainnetController.aave_getDepositRateLimitKey(SparkLend.PYUSD_SPTOKEN, address(POOL), Ethereum.PYUSD),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        rateLimits.setRateLimitData(
            mainnetController.aave_getWithdrawRateLimitKey(SparkLend.PYUSD_SPTOKEN, address(POOL)),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        // Empty the PYUSD pool.
        POOL.withdraw(
            Ethereum.PYUSD,
            PYUSD_SPTOKEN.balanceOf(Ethereum.SPARK_PROXY),
            Ethereum.SPARK_PROXY
        );

        // Set premium for flash loans to 0.09%
        IPoolConfiguratorLike(SparkLend.POOL_CONFIGURATOR).updateFlashloanPremiumTotal(9);

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23118264;
    }

}

contract MainnetController_AaveV3_LiquidityIndexInflationAttack_Test is AaveV3_Attack_TestBase {

    function test_depositAave_liquidityIndexInflationAttackFailure() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 1e18 - 1e4);  // Rounding slippage

        _doInflationAttack();

        // Verify that deposit would fail due to slippage
        deal(Ethereum.PYUSD, address(almProxy), 100_000e6);

        vm.expectRevert("AaveFacet/slippage-too-high");
        vm.prank(allocator);
        mainnetController.aave_deposit(SparkLend.PYUSD_SPTOKEN, 100_000e6);
    }

    function test_depositAave_liquidityIndexInflationAttackSuccess() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.aave_setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 1);

        _doInflationAttack();

        // Deposit would succeed without slippage
        deal(Ethereum.PYUSD, address(almProxy), 100_000e6);

        assertEq(PYUSD.balanceOf(address(almProxy)),         100_000e6);
        assertEq(PYUSD_SPTOKEN.balanceOf(address(almProxy)), 0);

        vm.prank(allocator);
        mainnetController.aave_deposit(SparkLend.PYUSD_SPTOKEN, 100_000e6);

        // Amount of aPYUSD received is less than the deposited amount due to slippage
        assertEq(PYUSD.balanceOf(address(almProxy)),  0);
        assertEq(PYUSD_SPTOKEN.balanceOf(address(almProxy)), 99_000.000011e6);

        // Attacker withdraws their share
        POOL.withdraw(
            Ethereum.PYUSD,
            PYUSD_SPTOKEN.balanceOf(address(this)),
            address(this)
        );

        // User withdraws getting less than what they deposited

        assertEq(PYUSD.balanceOf(address(almProxy)),         0);
        assertEq(PYUSD_SPTOKEN.balanceOf(address(almProxy)), 99_000.000011e6);

        vm.prank(allocator);
        mainnetController.aave_withdraw(SparkLend.PYUSD_SPTOKEN, 99_000.000011e6);

        assertEq(PYUSD.balanceOf(address(almProxy)),         99_000.000011e6);
        assertEq(PYUSD_SPTOKEN.balanceOf(address(almProxy)), 0);
    }

    function _doInflationAttack() internal {
        // Step 1: Initial setup - Start with empty pool
        // The pool should have minimal liquidity from fork state
        assertEq(PYUSD_SPTOKEN.totalSupply(),              0);
        assertEq(PYUSD.balanceOf(SparkLend.PYUSD_SPTOKEN), 0);

        // Get initial liquidity index (should be 1 RAY = 1e27)
        DataTypes.ReserveDataLegacy memory reserveData = POOL.getReserveData(Ethereum.PYUSD);
        uint256 initialLiquidityIndex = uint256(reserveData.liquidityIndex);
        assertEq(initialLiquidityIndex, 1e27);

        // Step 2: Attacker deposits funds into empty pool
        uint256 flashLoanAmount = 10_000_000e6;
        deal(Ethereum.PYUSD, address(this), flashLoanAmount);
        PYUSD.approve(SparkLend.POOL, flashLoanAmount);

        // Deposit to get aTokens and establish exchange rate
        POOL.supply(Ethereum.PYUSD, flashLoanAmount, address(this), 0);

        // Step 3: Attacker takes second flash loan for entire deposited amount
        // This will empty the aToken balance but keep totalSupply and liquidityIndex unchanged
        address[] memory assets = new address[](1);
        assets[0] = Ethereum.PYUSD;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAmount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        // Flash loan callback will handle the attack
        POOL.flashLoan(
            address(this),
            assets,
            amounts,
            interestRateModes,
            address(this),
            "",
            0
        );

        // Step 4: Verify the attack results
        // Check that liquidity index has been inflated
        DataTypes.ReserveDataLegacy memory finalReserveData = POOL.getReserveData(Ethereum.PYUSD);
        uint256 finalLiquidityIndex = uint256(finalReserveData.liquidityIndex);

        // The liquidity index should be much higher than 1 RAY due to the attack
        assertGt(finalLiquidityIndex, initialLiquidityIndex);
    }

    // Flash loan callback function
    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata,
        address,
        bytes     calldata
    ) external returns (bool) {
        require(msg.sender == SparkLend.POOL, "Only pool can call this");

        uint256 flashLoanAmount = amounts[0];

        // Step 4: Transfer underlying tokens directly to aToken balance
        // This bypasses the deposit function, so no new aTokens are minted
        PYUSD.transfer(SparkLend.PYUSD_SPTOKEN, flashLoanAmount);

        // Step 5: Withdraw all but 1 aToken
        // This makes totalSupply = 1 while liquidityIndex remains unchanged
        uint256 aTokenBalance  = PYUSD_SPTOKEN.balanceOf(address(this));
        uint256 withdrawAmount = aTokenBalance - 1; // Leave 1 aToken

        if (withdrawAmount > 0) {
            POOL.withdraw(Ethereum.PYUSD, withdrawAmount, address(this));
        }

        // Verify we have exactly 1 aToken left
        assertEq(PYUSD_SPTOKEN.balanceOf(address(this)), 1);

        // Step 6: Repay the flash loan with premium
        // Since totalSupply = 1, all the premium goes to the single share
        // This drastically increases liquidityIndex
        uint256 premium          = (flashLoanAmount * 9) / 10000; // 0.09% premium
        uint256 totalRepayAmount = flashLoanAmount + premium;

        // We need to have enough PYUSD to repay
        deal(Ethereum.PYUSD, address(this), totalRepayAmount);
        PYUSD.approve(SparkLend.POOL, totalRepayAmount);

        return true;
    }

}
