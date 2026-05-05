// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { SparkVault } from "../../lib/spark-vaults-v2/src/SparkVault.sol";

import { ISparkVaultFacet } from "../../src/facets/spark-vault/ISparkVaultFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

}

abstract contract SparkVault_TestBase is ForkTestBase {

    struct TestState {
        uint256 rateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    IERC20Like internal constant USDC_BASE = IERC20Like(Base.USDC);

    address internal user = makeAddr("user");

    bytes32 internal takeKey;

    SparkVault internal sparkVault;

    function setUp() public virtual override {
        super.setUp();

        sparkVault = SparkVault(
            address(new ERC1967Proxy(
                address(new SparkVault()),
                abi.encodeCall(
                    SparkVault.initialize,
                    (Base.USDC, "Spark Savings USDC V2", "spUSDC", Base.SPARK_EXECUTOR)
                )
            ))
        );

        takeKey = foreignController.getSparkVaultTakeRateLimitKey(address(sparkVault));

        vm.startPrank(Base.SPARK_EXECUTOR);
        sparkVault.grantRole(sparkVault.TAKER_ROLE(), address(almProxy));
        rateLimits.setRateLimitData(takeKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 34717833;  // August 26, 2025
    }

    function _assertTestState(TestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey),  state.rateLimit,        tolerance, "rateLimit");
        assertApproxEqAbs(USDC_BASE.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(USDC_BASE.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                 state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                 state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertTestState(TestState memory state) internal view {
        _assertTestState(state, 0);
    }

}

contract ForeignController_SparkVault_TakeFrom_Tests is SparkVault_TestBase {

    function test_takeFromSparkVault_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_zeroMaxAmount() external {
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(takeKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(Base.USDC, user, 10_000_000e6);
        vm.startPrank(user);
        USDC_BASE.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, user);
        vm.stopPrank();

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(takeKey, 10_000_000e6, uint256(10_000_000e6) / 1 days);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 10_000_000e6 + 1);

        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 10_000_000e6);
    }

    function test_takeFromSparkVault_rateLimited() external {
        deal(Base.USDC, user, 10_000_000e6);
        vm.startPrank(user);
        USDC_BASE.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, user);
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        1_000_000e6,
            usdcAlm:          0,
            usdcVault:        10_000_000e6,
            vaultTotalAssets: 10_000_000e6,
            vaultTotalSupply: 10_000_000e6
        });

        _assertTestState(testState);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), 1_000_000e6);

        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        testState.rateLimit -= 1_000_000e6;  // Rate limit goes down
        testState.usdcAlm   += 1_000_000e6;  // The almProxy receives the taken amount
        testState.usdcVault -= 1_000_000e6;  // The vault's usdc balance decreases

        _assertTestState(testState);

        skip(1 hours);

        // 1/24th of the rate limit per hour
        uint256 rateLimitIncreaseInOneHour = uint256(1_000_000e6) / (1 days) * (1 hours);
        assertEq(rateLimitIncreaseInOneHour, 41666.666400e6);

        testState.rateLimit += rateLimitIncreaseInOneHour;

        _assertTestState(testState);

        vm.expectEmit(address(foreignController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), rateLimitIncreaseInOneHour);

        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), rateLimitIncreaseInOneHour);

        testState.rateLimit -= rateLimitIncreaseInOneHour;  // Rate limit goes down
        testState.usdcAlm   += rateLimitIncreaseInOneHour;  // The almProxy receives the taken amount
        testState.usdcVault -= rateLimitIncreaseInOneHour;  // The vault's usdc balance decreases

        _assertTestState(testState);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 1);
    }

    function testFuzz_takeFromSparkVault(uint256 depositAmount, uint256 takeAmount) external {
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(takeKey, 10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);

        depositAmount = _bound(depositAmount, 1e18, 10_000_000_000e18);
        takeAmount    = _bound(depositAmount, 1e18, depositAmount);

        deal(Base.USDC, user, depositAmount);
        vm.startPrank(user);
        USDC_BASE.approve(address(sparkVault), depositAmount);
        sparkVault.deposit(depositAmount, user);
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        10_000_000_000e18,
            usdcAlm:          0,
            usdcVault:        depositAmount,
            vaultTotalAssets: depositAmount,
            vaultTotalSupply: depositAmount
        });

        _assertTestState(testState);

        vm.expectEmit(address(foreignController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), takeAmount);

        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), takeAmount);

        testState.rateLimit -= takeAmount;  // Rate limit goes down
        testState.usdcAlm   += takeAmount;  // The almProxy receives the taken amount
        testState.usdcVault -= takeAmount;  // The vault's usdc balance decreases

        _assertTestState(testState);
    }

}

contract ForeignController_SparkVault_TakeFrom_E2ETests is SparkVault_TestBase {

    struct E2ETestState {
        uint256 takeRateLimit;
        uint256 transferRateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultAssetsOut;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    bytes32 internal transferKey;

    function setUp() public override {
        // Step 1: Deploy the spark vault

        super.setUp();

        // Step 2 (spell): Grant roles to the almProxy and setter, set VSR bounds

        vm.startPrank(Base.SPARK_EXECUTOR);

        sparkVault.grantRole(sparkVault.SETTER_ROLE(), allocator);

        sparkVault.setVsrBounds(1e27, 1.000000003022265980097387650e27);  // 0% to 10% APY

        // Step 3 (spell): Set the rate limits

        transferKey = foreignController.getTransferAssetTransferRateLimitKey(Base.USDC, address(sparkVault));

        bytes32 morphoDepositKey  = foreignController.getERC4626DepositRateLimitKey(Base.MORPHO_VAULT_SUSDC, Base.USDC);
        bytes32 morphoWithdrawKey = foreignController.getERC4626WithdrawRateLimitKey(Base.MORPHO_VAULT_SUSDC);

        rateLimits.setRateLimitData(takeKey,          10_000_000e6, uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(transferKey,      10_000_000e6, uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(morphoDepositKey, 10_000_000e6, uint256(10_000_000e6) / 1 days);

        rateLimits.setUnlimitedRateLimitData(morphoWithdrawKey);

        // Step 4 (spell): Set maxExchangeRate for ERC4626 deposit

        foreignController.setMaxExchangeRate(Base.MORPHO_VAULT_SUSDC, 1e18, 1.2e18);

        vm.stopPrank();
    }

    function _assertE2EState(E2ETestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey),     state.takeRateLimit,     tolerance, "takeRateLimit");
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(transferKey), state.transferRateLimit, tolerance, "transferRateLimit");

        assertApproxEqAbs(USDC_BASE.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(USDC_BASE.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                 state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                 state.vaultTotalSupply, tolerance, "vaultTotalSupply");
        assertApproxEqAbs(sparkVault.assetsOutstanding(),           state.vaultAssetsOut,   tolerance, "vaultAssetsOut");
    }

    function _assertE2EState(E2ETestState memory state) internal view {
        _assertE2EState(state, 0);
    }

    function test_e2e_takeFromSparkVault() external {
        // Step 1: Set the initial state

        E2ETestState memory testState = E2ETestState({
            takeRateLimit:     10_000_000e6,
            transferRateLimit: 10_000_000e6,
            usdcAlm:           0,
            usdcVault:         0,
            vaultAssetsOut:    0,
            vaultTotalAssets:  0,
            vaultTotalSupply:  0
        });

        _assertE2EState(testState);

        skip(1 days);

        // Step 2: Deposit usdc into the spark vault

        deal(Base.USDC, user, 10_000_000e6);
        vm.startPrank(user);
        USDC_BASE.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, user);
        vm.stopPrank();

        testState.usdcVault        = 10_000_000e6;
        testState.vaultTotalAssets = 10_000_000e6;
        testState.vaultTotalSupply = 10_000_000e6;

        _assertE2EState(testState);

        skip(1 days);

        // Step 3: Take usdc from the spark vault

        vm.prank(allocator);
        foreignController.takeFromSparkVault(address(sparkVault), 9_000_000e6);

        testState.takeRateLimit  = 1_000_000e6;
        testState.usdcAlm        = 9_000_000e6;
        testState.usdcVault      = 1_000_000e6;
        testState.vaultAssetsOut = 9_000_000e6;

        _assertE2EState(testState);

        skip(10 days);  // Get full rate limit for Morpho deposit

        // Step 4: Deposit into Morpho and set the VSR to 4% APY

        vm.startPrank(allocator);
        uint256 shares = foreignController.depositERC4626(Base.MORPHO_VAULT_SUSDC, 9_000_000e6, 0);
        sparkVault.setVsr(1.000000001243680656318820312e27);  // 4% APY
        vm.stopPrank();

        testState.takeRateLimit = 10_000_000e6;
        testState.usdcAlm       = 0;

        _assertE2EState(testState);  // No state changes

        skip(365 days);

        // Step 5: Show state change after a year (easiest for APY assertions)

        // 4% APY on 10m USDC = 500k USDC
        // NOTE: The APY is on the full value of the vault, NOT the take amount.
        testState.vaultTotalAssets = 10_400_000e6 - 1;  // Rounding
        testState.vaultAssetsOut   = 9_400_000e6 - 1;   // Rounding

        _assertE2EState(testState);

        // Step 6: Redeem assets from Morpho, swap DAI to USDC and transfer outstanding assets to the vault

        vm.startPrank(allocator);
        uint256 assets = foreignController.redeemERC4626(Base.MORPHO_VAULT_SUSDC, shares, 0);
        foreignController.transferAsset(Base.USDC, address(sparkVault), 9_400_000e6);
        vm.stopPrank();

        assertEq(assets, 9_424_512.250438e6);  // ~414k in yield

        uint256 almProfit = assets - 9_400_000e6;  // 9.4m owed to the vault

        testState.transferRateLimit = 600_000e6;  // 10m - 9.4m
        testState.usdcAlm           = almProfit;
        testState.usdcVault         = 10_400_000e6;
        testState.vaultAssetsOut    = 0;

        _assertE2EState(testState);

        // Step 7: User withdraws all assets

        vm.startPrank(user);
        sparkVault.withdraw(sparkVault.assetsOf(user), user, user);
        vm.stopPrank();

        // Vault is empty and ALM system has some profit
        _assertE2EState(E2ETestState({
            takeRateLimit:     10_000_000e6,
            transferRateLimit: 600_000e6,
            usdcAlm:           almProfit,
            usdcVault:         1,  // Rounding against user
            vaultAssetsOut:    0,
            vaultTotalAssets:  0,
            vaultTotalSupply:  0
        }));

        // User has all funds, and has earned a 4% APY on their deposit
        assertEq(USDC_BASE.balanceOf(user), 10_400_000e6 - 1);  // Rounding against user
    }

}
