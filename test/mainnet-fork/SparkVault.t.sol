// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC1967Proxy }    from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

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

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

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
                    (Ethereum.USDC, "Spark Savings USDC V2", "spUSDC", Ethereum.SPARK_PROXY)
                )
            ))
        );

        takeKey = mainnetController.getSparkVaultTakeRateLimitKey(address(sparkVault));

        vm.startPrank(Ethereum.SPARK_PROXY);
        sparkVault.grantRole(sparkVault.TAKER_ROLE(), address(almProxy));
        rateLimits.setRateLimitData(takeKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function _assertTestState(TestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey), state.rateLimit,        tolerance, "rateLimit");
        assertApproxEqAbs(USDC.balanceOf(address(almProxy)),       state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(USDC.balanceOf(address(sparkVault)),     state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertTestState(TestState memory state) internal view {
        _assertTestState(state, 0);
    }
}

contract MainnetController_SparkVault_TakeFrom_Tests is SparkVault_TestBase {

    function test_takeFromSparkVault_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(Ethereum.USDC, user, 10_000_000e6);

        vm.startPrank(user);
        USDC.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, user);
        vm.stopPrank();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey, 10_000_000e6, uint256(10_000_000e6) / 1 days);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e6);
    }

    function test_takeFromSparkVault_rateLimited() external {
        deal(Ethereum.USDC, user, 10_000_000e6);

        vm.startPrank(user);
        USDC.approve(address(sparkVault), 10_000_000e6);
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

        vm.expectEmit(address(mainnetController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 1_000_000e6);

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

        vm.expectEmit(address(mainnetController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), rateLimitIncreaseInOneHour);

        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), rateLimitIncreaseInOneHour);

        testState.rateLimit -= rateLimitIncreaseInOneHour;  // Rate limit goes down
        testState.usdcAlm   += rateLimitIncreaseInOneHour;  // The almProxy receives the taken amount
        testState.usdcVault -= rateLimitIncreaseInOneHour;  // The vault's usdc balance decreases

        _assertTestState(testState);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 1);
    }

    function testFuzz_takeFromSparkVault(uint256 depositAmount, uint256 takeAmount) external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey, 10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);

        depositAmount = _bound(depositAmount, 1e18, 10_000_000_000e18);
        takeAmount    = _bound(depositAmount, 1e18, depositAmount);

        deal(Ethereum.USDC, user, depositAmount);

        vm.startPrank(user);
        USDC.approve(address(sparkVault), depositAmount);
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

        vm.expectEmit(address(mainnetController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), takeAmount);

        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), takeAmount);

        testState.rateLimit -= takeAmount;  // Rate limit goes down
        testState.usdcAlm   += takeAmount;  // The almProxy receives the taken amount
        testState.usdcVault -= takeAmount;  // The vault's usdc balance decreases

        _assertTestState(testState);
    }

}

contract MainnetController_SparkVault_TakeFrom_E2ETests is SparkVault_TestBase {

    struct E2ETestState {
        uint256 takeRateLimit;
        uint256 transferRateLimit;
        uint256 daiAlm;
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

        vm.startPrank(Ethereum.SPARK_PROXY);

        sparkVault.grantRole(sparkVault.SETTER_ROLE(), allocator);

        sparkVault.setVsrBounds(1e27, 1.000000003022265980097387650e27);  // 0% to 10% APY

        // Step 3 (spell): Set the rate limits

        transferKey = mainnetController.getTransferAssetTransferRateLimitKey(Ethereum.USDC, address(sparkVault));

        bytes32 morphoDepositKey  = mainnetController.getERC4626DepositRateLimitKey(Ethereum.MORPHO_VAULT_DAI_1, Ethereum.DAI);
        bytes32 morphoWithdrawKey = mainnetController.getERC4626WithdrawRateLimitKey(Ethereum.MORPHO_VAULT_DAI_1);

        rateLimits.setRateLimitData(takeKey,          10_000_000e6,  uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(transferKey,      10_000_000e6,  uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(morphoDepositKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        rateLimits.setRateLimitData(
            mainnetController.psmUSDSToUSDCSwapRateLimitKey(),
            10_000_000e6,
            uint256(10_000_000e6) / 1 days
        );

        rateLimits.setUnlimitedRateLimitData(morphoWithdrawKey);

        // Step 4 (spell): Set maxSlippage for ERC4626 deposit

        mainnetController.setMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1, 1e18, 1.2e18);

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23226130;  // August 22, 2025
    }

    function _assertE2EState(E2ETestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey),     state.takeRateLimit,     tolerance, "takeRateLimit");
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(transferKey), state.transferRateLimit, tolerance, "transferRateLimit");

        assertApproxEqAbs(dai.balanceOf(address(almProxy)),    state.daiAlm,           tolerance, "daiAlm");
        assertApproxEqAbs(USDC.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(USDC.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),            state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),            state.vaultTotalSupply, tolerance, "vaultTotalSupply");
        assertApproxEqAbs(sparkVault.assetsOutstanding(),      state.vaultAssetsOut,   tolerance, "vaultAssetsOut");
    }

    function _assertE2EState(E2ETestState memory state) internal view {
        _assertE2EState(state, 0);
    }

    function test_e2e_takeFromSparkVault() external {
        // Step 1: Set the initial state

        E2ETestState memory testState = E2ETestState({
            takeRateLimit:     10_000_000e6,
            transferRateLimit: 10_000_000e6,
            daiAlm:            0,
            usdcAlm:           0,
            usdcVault:         0,
            vaultAssetsOut:    0,
            vaultTotalAssets:  0,
            vaultTotalSupply:  0
        });

        _assertE2EState(testState);

        skip(1 days);

        // Step 2: Deposit usdc into the spark vault

        deal(Ethereum.USDC, user, 10_000_000e6);

        vm.startPrank(user);
        USDC.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, user);
        vm.stopPrank();

        testState.usdcVault        = 10_000_000e6;
        testState.vaultTotalAssets = 10_000_000e6;
        testState.vaultTotalSupply = 10_000_000e6;

        _assertE2EState(testState);

        skip(1 days);

        // Step 3: Take usdc from the spark vault

        vm.expectEmit(address(mainnetController));
        emit ISparkVaultFacet.SparkVaultTake(address(sparkVault), 9_000_000e6);

        vm.prank(allocator);
        mainnetController.takeFromSparkVault(address(sparkVault), 9_000_000e6);

        testState.takeRateLimit  = 1_000_000e6;
        testState.usdcAlm        = 9_000_000e6;
        testState.usdcVault      = 1_000_000e6;
        testState.vaultAssetsOut = 9_000_000e6;

        _assertE2EState(testState);

        skip(10 days);  // Get full rate limit for Morpho deposit

        // Step 4: Swap into DAI, deposit into Morpho, and set the VSR to 4% APY

        vm.startPrank(allocator);
        mainnetController.swapUSDCToUSDS(9_000_000e6);
        mainnetController.swapUSDSToDAI(9_000_000e18);
        uint256 shares = mainnetController.depositERC4626(Ethereum.MORPHO_VAULT_DAI_1, 9_000_000e18, 0);
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
        uint256 assets = mainnetController.redeemERC4626(Ethereum.MORPHO_VAULT_DAI_1, shares, 0);
        mainnetController.swapDAIToUSDS(9_400_000e18);
        mainnetController.swapUSDSToUSDC(9_400_000e6);
        mainnetController.transferAsset(Ethereum.USDC, address(sparkVault), 9_400_000e6);
        vm.stopPrank();

        assertEq(assets, 9_414_173.844477081922732043e18);  // ~414k in yield

        uint256 almProfit = assets - 9_400_000e18;  // 9.4m owed to the vault

        testState.transferRateLimit = 600_000e6;  // 10m - 9.4m
        testState.daiAlm            = almProfit;
        testState.usdcAlm           = 0;
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
            daiAlm:            14_173.844477081922732043e18,  // Profit
            usdcAlm:           0,
            usdcVault:         1,  // Rounding against user
            vaultAssetsOut:    0,
            vaultTotalAssets:  0,
            vaultTotalSupply:  0
        }));

        // User has all funds, and has earned a 4% APY on their deposit
        assertEq(USDC.balanceOf(user), 10_400_000e6 - 1);  // Rounding against user
    }

}
