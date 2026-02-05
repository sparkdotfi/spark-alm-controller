// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { DataTypes } from "../../lib/aave-v3-origin/src/core/contracts/protocol/libraries/types/DataTypes.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum }  from "../../lib/spark-address-registry/src/Ethereum.sol";
import { SparkLend } from "../../lib/spark-address-registry/src/SparkLend.sol";

import { makeAddressKey } from "../../src/RateLimitHelpers.sol";

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

abstract contract AaveV3_Market_TestBase is ForkTestBase {

    address constant ATOKEN_USDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant POOL        = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    uint256 startingAUSDSBalance;
    uint256 startingAUSDCBalance;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(), ATOKEN_USDS),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(), ATOKEN_USDC),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDS),
            10_000_000e18,
            uint256(5_000_000e18) / 1 days
        );

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDC),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        mainnetController.setMaxSlippage(ATOKEN_USDS, 1e18 - 1e4);  // Rounding slippage
        mainnetController.setMaxSlippage(ATOKEN_USDC, 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();

        startingAUSDCBalance = usdc.balanceOf(ATOKEN_USDC);
        startingAUSDSBalance = usds.balanceOf(ATOKEN_USDS);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used

contract MainnetController_AaveV3_MarketDeposit_Tests is AaveV3_Market_TestBase {

    function test_depositAave_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_zeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.depositAave(makeAddr("fake-token"), 1e18);
    }

    function test_depositAave_zeroMaxSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDS, 0);

        vm.expectRevert("AaveLib/max-slippage-not-set");
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1e18);
    }

    function test_depositAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18);
    }

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6);
    }

    function test_depositAave_usdsSlippageBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        // Positive slippage because of no rounding error
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDS, 1e18 + 1);

        vm.expectRevert("AaveLib/slippage-too-high");
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 5_000_000e18);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDS, 1e18);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 5_000_000e18);
    }

    function test_depositAave_usdcSlippageBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 5_000_000e6);

        // Positive slippage because of no rounding error
        // 0.2e6 * 5_000_000e6 / 1e18 = 1
        // (0.2e6 - 1) * 5_000_000e6 / 1e18 = 0
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDC, 1e18 + 0.2e6);

        vm.expectRevert("AaveLib/slippage-too-high");
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 5_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDC, 1e18 + 0.2e6 - 1);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 5_000_000e6);
    }

    function test_depositAave_usds() external {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),                    1_000_000e18);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance);

        vm.record();

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),                    0);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 1_000_000e18);
    }

    function test_depositAave_usdc() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),                    1_000_000e6);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance);

        vm.record();

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),                    0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 1_000_000e6);
    }

}

contract MainnetController_AaveV3_MarketWithdraw_Tests is AaveV3_Market_TestBase {

    function test_withdrawAave_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.withdrawAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_withdrawAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.withdrawAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_withdrawAave_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDC),
            0,
            0
        );
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.withdrawAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_withdrawAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 15_000_000e18);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDS, 15_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18 + 1);

        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 15_000_000e6);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDC, 15_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6 + 1);

        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6);

        vm.stopPrank();
    }

    function test_withdrawAave_usds() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  ATOKEN_USDS);
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDS);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),                    0);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 1_000_000e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        vm.record();

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, 400_000e18), 400_000e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), aTokenBalance - 400_000e18);
        assertEq(usds.balanceOf(address(almProxy)),                    400_000e18);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 600_000e18);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e18);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), aTokenBalance - 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18 - aTokenBalance);

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),                    aTokenBalance);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 1_000_000e18 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usds.balanceOf(ATOKEN_USDS), startingAUSDSBalance);
    }

    function test_withdrawAave_usds_unlimitedRateLimit() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(),   ATOKEN_USDS);
        bytes32 withdrawKey = makeAddressKey( mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDS);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),                    0);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 1_000_000e18);

        // Full withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(IERC20Like(ATOKEN_USDS).balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),                    aTokenBalance);
        assertEq(usds.balanceOf(ATOKEN_USDS),                          startingAUSDSBalance + 1_000_000e18 - aTokenBalance);
    }

    function test_withdrawAave_usdc() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  ATOKEN_USDC);
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDC);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),                    0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 1_000_000e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), aTokenBalance - 400_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),                    400_000e6);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 600_000e6);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e6);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance - 400_000e6);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),                    aTokenBalance);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 1_000_000e6 - aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usdc.balanceOf(ATOKEN_USDC), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() external {
        bytes32 depositKey  = makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  ATOKEN_USDC);
        bytes32 withdrawKey = makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), ATOKEN_USDC);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),                    0);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 1_000_000e6);

        // Full withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(IERC20Like(ATOKEN_USDC).balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),                    aTokenBalance);
        assertEq(usdc.balanceOf(ATOKEN_USDC),                          startingAUSDCBalance + 1_000_000e6 - aTokenBalance);
    }

}

abstract contract AaveV3_MarketAttack_TestBase is ForkTestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(), SparkLend.PYUSD_SPTOKEN),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        rateLimits.setRateLimitData(
            makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), SparkLend.PYUSD_SPTOKEN),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        // Empty the PYUSD pool.
        IAavePoolLike(SparkLend.POOL).withdraw(
            Ethereum.PYUSD,
            IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY),
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

contract MainnetController_AaveV3_MarketLiquidityIndexInflationAttack_Test is AaveV3_MarketAttack_TestBase {

    function test_depositAave_liquidityIndexInflationAttackFailure() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 1e18 - 1e4);  // Rounding slippage

        _doInflationAttack();

        // Verify that deposit would fail due to slippage
        deal(Ethereum.PYUSD, address(almProxy), 100_000e6);

        vm.expectRevert("AaveLib/slippage-too-high");
        vm.prank(relayer);
        mainnetController.depositAave(SparkLend.PYUSD_SPTOKEN, 100_000e6);
    }

    function test_depositAave_liquidityIndexInflationAttackSuccess() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 1);

        _doInflationAttack();

        // Deposit would succeed without slippage
        deal(Ethereum.PYUSD, address(almProxy), 100_000e6);

        assertEq(IERC20Like(Ethereum.PYUSD).balanceOf(address(almProxy)),  100_000e6);
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositAave(SparkLend.PYUSD_SPTOKEN, 100_000e6);

        // Amount of aPYUSD received is less than the deposited amount due to slippage
        assertEq(IERC20Like(Ethereum.PYUSD).balanceOf(address(almProxy)),  0);
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(almProxy)), 99_000.000011e6);

        // Attacker withdraws their share
        IAavePoolLike(SparkLend.POOL).withdraw(
            Ethereum.PYUSD,
            IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(this)),
            address(this)
        );

        // User withdraws getting less than what they deposited

        assertEq(IERC20Like(Ethereum.PYUSD).balanceOf(address(almProxy)),  0);
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(almProxy)), 99_000.000011e6);

        vm.prank(relayer);
        mainnetController.withdrawAave(SparkLend.PYUSD_SPTOKEN, 99_000.000011e6);

        assertEq(IERC20Like(Ethereum.PYUSD).balanceOf(address(almProxy)),  99_000.000011e6);
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(almProxy)), 0);
    }

    function _doInflationAttack() internal {
        // Step 1: Initial setup - Start with empty pool
        // The pool should have minimal liquidity from fork state
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).totalSupply(),             0);
        assertEq(IERC20Like(Ethereum.PYUSD).balanceOf(SparkLend.PYUSD_SPTOKEN), 0);

        // Get initial liquidity index (should be 1 RAY = 1e27)
        DataTypes.ReserveDataLegacy memory reserveData = IAavePoolLike(SparkLend.POOL).getReserveData(Ethereum.PYUSD);
        uint256 initialLiquidityIndex = uint256(reserveData.liquidityIndex);
        assertEq(initialLiquidityIndex, 1e27);

        // Step 2: Attacker deposits funds into empty pool
        uint256 flashLoanAmount = 10_000_000e6;
        deal(Ethereum.PYUSD, address(this), flashLoanAmount);
        IERC20Like(Ethereum.PYUSD).approve(SparkLend.POOL, flashLoanAmount);

        // Deposit to get aTokens and establish exchange rate
        IAavePoolLike(SparkLend.POOL).supply(Ethereum.PYUSD, flashLoanAmount, address(this), 0);

        // Step 3: Attacker takes second flash loan for entire deposited amount
        // This will empty the aToken balance but keep totalSupply and liquidityIndex unchanged
        address[] memory assets = new address[](1);
        assets[0] = Ethereum.PYUSD;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAmount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        // Flash loan callback will handle the attack
        IAavePoolLike(SparkLend.POOL).flashLoan(
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
        DataTypes.ReserveDataLegacy memory finalReserveData = IAavePoolLike(SparkLend.POOL).getReserveData(Ethereum.PYUSD);
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
        IERC20Like(Ethereum.PYUSD).transfer(SparkLend.PYUSD_SPTOKEN, flashLoanAmount);

        // Step 5: Withdraw all but 1 aToken
        // This makes totalSupply = 1 while liquidityIndex remains unchanged
        uint256 aTokenBalance  = IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(this));
        uint256 withdrawAmount = aTokenBalance - 1; // Leave 1 aToken

        if (withdrawAmount > 0) {
            IAavePoolLike(SparkLend.POOL).withdraw(Ethereum.PYUSD, withdrawAmount, address(this));
        }

        // Verify we have exactly 1 aToken left
        assertEq(IERC20Like(SparkLend.PYUSD_SPTOKEN).balanceOf(address(this)), 1);

        // Step 6: Repay the flash loan with premium
        // Since totalSupply = 1, all the premium goes to the single share
        // This drastically increases liquidityIndex
        uint256 premium          = (flashLoanAmount * 9) / 10000; // 0.09% premium
        uint256 totalRepayAmount = flashLoanAmount + premium;

        // We need to have enough PYUSD to repay
        deal(Ethereum.PYUSD, address(this), totalRepayAmount);
        IERC20Like(Ethereum.PYUSD).approve(SparkLend.POOL, totalRepayAmount);

        return true;
    }

}
