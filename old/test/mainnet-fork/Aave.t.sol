// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";
import { DataTypes }          from "aave-v3-origin/src/core/contracts/protocol/libraries/types/DataTypes.sol";
import { IPoolConfigurator }  from "aave-v3-origin/src/core/contracts/interfaces/IPoolConfigurator.sol";

import "./ForkTestBase.t.sol";

contract AaveV3MainMarketBaseTest is ForkTestBase {

    address constant ATOKEN_USDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant POOL        = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    IAToken ausds = IAToken(ATOKEN_USDS);
    IAToken ausdc = IAToken(ATOKEN_USDC);

    uint256 startingAUSDSBalance;
    uint256 startingAUSDCBalance;

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDS
            ),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_DEPOSIT(),
                ATOKEN_USDC
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDS
            ),
            10_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        mainnetController.setMaxSlippage(ATOKEN_USDS, 1e18 - 1e4);  // Rounding slippage
        mainnetController.setMaxSlippage(ATOKEN_USDC, 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();

        startingAUSDCBalance = usdc.balanceOf(address(ausdc));
        startingAUSDSBalance = usds.balanceOf(address(ausds));
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used

contract AaveV3MainMarketDepositFailureTests is AaveV3MainMarketBaseTest {

    function test_depositAave_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);
    }

    function test_depositAave_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositAave(makeAddr("fake-token"), 1e18);
    }

    function test_depositAave_zeroMaxSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDS, 0);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/max-slippage-not-set");
        mainnetController.depositAave(ATOKEN_USDS, 1e18);
    }

    function test_depositAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18 + 1);

        mainnetController.depositAave(ATOKEN_USDS, 25_000_000e18);
    }

    function test_depositAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6 + 1);

        mainnetController.depositAave(ATOKEN_USDC, 25_000_000e6);
    }

    function test_depositAave_usdsSlippageBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 5_000_000e18);

        // Positive slippage because of no rounding error
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDS, 1e18 + 1);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/slippage-too-high");
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

        vm.prank(relayer);
        vm.expectRevert("MainnetController/slippage-too-high");
        mainnetController.depositAave(ATOKEN_USDC, 5_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(ATOKEN_USDC, 1e18 + 0.2e6 - 1);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 5_000_000e6);
    }

}

contract AaveV3MainMarketDepositSuccessTests is AaveV3MainMarketBaseTest {

    function test_depositAave_usds() public {
        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  1_000_000e18);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        assertEq(usds.allowance(address(almProxy), POOL), 0);

        assertEq(ausds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);
    }

    function test_depositAave_usdc() public {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance);

        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), POOL), 0);

        assertEq(ausdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);
    }

}

contract AaveV3MainMarketWithdrawFailureTests is AaveV3MainMarketBaseTest {

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
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                ATOKEN_USDC
            ),
            0,
            0
        );
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawAave(ATOKEN_USDC, 1_000_000e6);
    }

    function test_withdrawAave_usdsRateLimitedBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 15_000_000e18);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDS, 15_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18 + 1);

        mainnetController.withdrawAave(ATOKEN_USDS, 10_000_000e18);
    }

    function test_withdrawAave_usdcRateLimitedBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 15_000_000e6);

        vm.startPrank(relayer);

        mainnetController.depositAave(ATOKEN_USDC, 15_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6 + 1);

        mainnetController.withdrawAave(ATOKEN_USDC, 10_000_000e6);
    }

}

contract AaveV3MainMarketWithdrawSuccessTests is AaveV3MainMarketBaseTest {

    function test_withdrawAave_usds() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDS
        );

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = ausds.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        assertEq(ausds.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, 400_000e18), 400_000e18);

        assertEq(ausds.balanceOf(address(almProxy)), aTokenBalance - 400_000e18);
        assertEq(usds.balanceOf(address(almProxy)),  400_000e18);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 600_000e18);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e18);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), aTokenBalance - 400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18 - aTokenBalance);

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usds.balanceOf(address(ausds)), startingAUSDSBalance);
    }

    function test_withdrawAave_usds_unlimitedRateLimit() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDS
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDS, 1_000_000e18);

        skip(1 hours);

        uint256 aTokenBalance = ausds.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_008.690632523560813345e18);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e18 + uint256(5_000_000e18) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(ausds.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usds.balanceOf(address(almProxy)),  0);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18);

        // Full withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDS, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(ausds.balanceOf(address(almProxy)), 0);
        assertEq(usds.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usds.balanceOf(address(ausds)),     startingAUSDSBalance + 1_000_000e18 - aTokenBalance);
    }

    function test_withdrawAave_usdc() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = ausdc.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        assertEq(ausdc.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6);

        // Partial withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, 400_000e6), 400_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)), aTokenBalance - 400_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  400_000e6);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 600_000e6);  // 1m - 400k

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit + 400_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_600_000e6);

        // Withdraw all
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance - 400_000e6);

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6 - aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e6 - aTokenBalance);

        // Interest accrued was withdrawn, reducing cash balance
        assertLt(usdc.balanceOf(address(ausdc)), startingAUSDCBalance);
    }

    function test_withdrawAave_usdc_unlimitedRateLimit() public {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_DEPOSIT(),
            ATOKEN_USDC
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_AAVE_WITHDRAW(),
            ATOKEN_USDC
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(withdrawKey);

        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        mainnetController.depositAave(ATOKEN_USDC, 1_000_000e6);

        skip(1 hours);

        uint256 aTokenBalance = ausdc.balanceOf(address(almProxy));

        assertEq(aTokenBalance, 1_000_013.630187e6);

        uint256 startingDepositRateLimit = rateLimits.getCurrentRateLimit(depositKey);

        assertEq(startingDepositRateLimit, 24_000_000e6 + uint256(5_000_000e6) / 1 days * 1 hours);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  startingDepositRateLimit);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(ausdc.balanceOf(address(almProxy)), aTokenBalance);
        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6);

        // Full withdraw
        vm.prank(relayer);
        assertEq(mainnetController.withdrawAave(ATOKEN_USDC, type(uint256).max), aTokenBalance);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  25_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);  // No change

        assertEq(ausdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  aTokenBalance);
        assertEq(usdc.balanceOf(address(ausdc)),     startingAUSDCBalance + 1_000_000e6 - aTokenBalance);
    }

}

contract AaveV3MainMarketAttackBaseTest is ForkTestBase {

    IAToken apyusd = IAToken(Ethereum.PYUSD_SPTOKEN);
    IERC20  pyusd  = IERC20(0x6c3ea9036406852006290770BEdFcAbA0e23A0e8);

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_DEPOSIT(),
                Ethereum.PYUSD_SPTOKEN
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_AAVE_WITHDRAW(),
                Ethereum.PYUSD_SPTOKEN
            ),
            10_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        // Empty the PYUSD pool.
        IAavePool(Ethereum.POOL).withdraw(address(pyusd), apyusd.balanceOf(Ethereum.SPARK_PROXY), Ethereum.SPARK_PROXY);

        // Set premium for flash loans to 0.09%
        IPoolConfigurator(Ethereum.POOL_CONFIGURATOR).updateFlashloanPremiumTotal(9);

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23118264;
    }

}

contract AaveV3MainMarketLiquidityIndexInflationAttackTest is AaveV3MainMarketAttackBaseTest {

    function test_depositAave_liquidityIndexInflationAttackFailure() public {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(Ethereum.PYUSD_SPTOKEN, 1e18 - 1e4);  // Rounding slippage

        _doInflationAttack();

        // Verify that deposit would fail due to slippage
        deal(address(pyusd), address(almProxy), 100_000e6);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/slippage-too-high");
        mainnetController.depositAave(Ethereum.PYUSD_SPTOKEN, 100_000e6);
    }

    function test_depositAave_liquidityIndexInflationAttackSuccess() public {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(Ethereum.PYUSD_SPTOKEN, 1);

        _doInflationAttack();

        // Deposit would succeed without slippage
        deal(address(pyusd), address(almProxy), 100_000e6);

        assertEq(pyusd.balanceOf(address(almProxy)),  100_000e6);
        assertEq(apyusd.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositAave(Ethereum.PYUSD_SPTOKEN, 100_000e6);

        // Amount of aPYUSD received is less than the deposited amount due to slippage
        assertEq(pyusd.balanceOf(address(almProxy)),  0);
        assertEq(apyusd.balanceOf(address(almProxy)), 99_000.000011e6);

        // Attacker withdraws their share
        IAavePool(Ethereum.POOL).withdraw(address(pyusd), apyusd.balanceOf(address(this)), address(this));

        // User withdraws getting less than what they deposited

        assertEq(pyusd.balanceOf(address(almProxy)),  0);
        assertEq(apyusd.balanceOf(address(almProxy)), 99_000.000011e6);

        vm.prank(relayer);
        mainnetController.withdrawAave(Ethereum.PYUSD_SPTOKEN, 99_000.000011e6);

        assertEq(pyusd.balanceOf(address(almProxy)),  99_000.000011e6);
        assertEq(apyusd.balanceOf(address(almProxy)), 0);
    }

    function _doInflationAttack() internal {
        // Step 1: Initial setup - Start with empty pool
        // The pool should have minimal liquidity from fork state
        assertEq(apyusd.totalSupply(),             0);
        assertEq(pyusd.balanceOf(address(apyusd)), 0);

        // Get initial liquidity index (should be 1 RAY = 1e27)
        DataTypes.ReserveDataLegacy memory reserveData = IAavePool(Ethereum.POOL).getReserveData(address(pyusd));
        uint256 initialLiquidityIndex = uint256(reserveData.liquidityIndex);
        assertEq(initialLiquidityIndex, 1e27);

        // Step 2: Attacker deposits funds into empty pool
        uint256 flashLoanAmount = 10_000_000e6;
        deal(address(pyusd), address(this), flashLoanAmount);
        pyusd.approve(Ethereum.POOL, flashLoanAmount);

        // Deposit to get aTokens and establish exchange rate
        IAavePool(Ethereum.POOL).supply(address(pyusd), flashLoanAmount, address(this), 0);

        // Step 3: Attacker takes second flash loan for entire deposited amount
        // This will empty the aToken balance but keep totalSupply and liquidityIndex unchanged
        address[] memory assets = new address[](1);
        assets[0] = address(pyusd);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAmount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        // Flash loan callback will handle the attack
        IAavePool(Ethereum.POOL).flashLoan(
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
        DataTypes.ReserveDataLegacy memory finalReserveData = IAavePool(Ethereum.POOL).getReserveData(address(pyusd));
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
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == Ethereum.POOL, "Only pool can call this");

        uint256 flashLoanAmount = amounts[0];

        // Step 4: Transfer underlying tokens directly to aToken balance
        // This bypasses the deposit function, so no new aTokens are minted
        pyusd.transfer(address(apyusd), flashLoanAmount);

        // Step 5: Withdraw all but 1 aToken
        // This makes totalSupply = 1 while liquidityIndex remains unchanged
        uint256 aTokenBalance  = apyusd.balanceOf(address(this));
        uint256 withdrawAmount = aTokenBalance - 1; // Leave 1 aToken

        if (withdrawAmount > 0) {
            IAavePool(Ethereum.POOL).withdraw(address(pyusd), withdrawAmount, address(this));
        }

        // Verify we have exactly 1 aToken left
        assertEq(apyusd.balanceOf(address(this)), 1);

        // Step 6: Repay the flash loan with premium
        // Since totalSupply = 1, all the premium goes to the single share
        // This drastically increases liquidityIndex
        uint256 premium          = (flashLoanAmount * 9) / 10000; // 0.09% premium
        uint256 totalRepayAmount = flashLoanAmount + premium;

        // We need to have enough PYUSD to repay
        deal(address(pyusd), address(this), totalRepayAmount);
        pyusd.approve(Ethereum.POOL, totalRepayAmount);

        return true;
    }

}
