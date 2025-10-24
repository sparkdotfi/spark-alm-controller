// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock as MockERC20 } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }           from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { SparkVault } from "spark-vaults-v2/src/SparkVault.sol";

import "./ForkTestBase.t.sol";

contract ForeignControllerTakeFromSparkVaultTestBase is ForkTestBase {

    struct TestState {
        uint256 rateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    address user = makeAddr("user");

    bytes32 LIMIT_SPARK_VAULT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    bytes32 key;

    SparkVault sparkVault;

    function setUp() public override {
        super.setUp();

        sparkVault = SparkVault(
            address(new ERC1967Proxy(
                address(new SparkVault()),
                abi.encodeCall(
                    SparkVault.initialize,
                    (address(usdcBase), "Spark Savings USDC V2", "spUSDC", Base.SPARK_EXECUTOR)
                )
            ))
        );

        key = RateLimitHelpers.makeAddressKey(
            LIMIT_SPARK_VAULT_TAKE,
            address(sparkVault)
        );

        vm.startPrank(Base.SPARK_EXECUTOR);
        sparkVault.grantRole(sparkVault.TAKER_ROLE(), address(almProxy));
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 34717833;  // August 26, 2025
    }

    function _assertTestState(TestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(key),     state.rateLimit,        tolerance, "rateLimit");
        assertApproxEqAbs(usdcBase.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(usdcBase.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertTestState(TestState memory state) internal view {
        _assertTestState(state, 0);
    }

}

contract ForeignControllerTakeFromSparkVaultFailureTests is ForeignControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_zeroMaxAmount() external {
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(address(usdcBase), address(user), 10_000_000e6);
        vm.startPrank(user);
        usdcBase.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, address(user));
        vm.stopPrank();

        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(key, 10_000_000e6, uint256(10_000_000e6) / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.takeFromSparkVault(address(sparkVault), 10_000_000e6 + 1);

        vm.prank(relayer);
        foreignController.takeFromSparkVault(address(sparkVault), 10_000_000e6);
    }

}

contract ForeignControllerTakeFromSparkVaultTests is ForeignControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_rateLimited() external {
        deal(address(usdcBase), address(user), 10_000_000e6);
        vm.startPrank(user);
        usdcBase.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, address(user));
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        1_000_000e6,
            usdcAlm:          0,
            usdcVault:        10_000_000e6,
            vaultTotalAssets: 10_000_000e6,
            vaultTotalSupply: 10_000_000e6
        });

        _assertTestState(testState);

        vm.prank(relayer);
        foreignController.takeFromSparkVault(address(sparkVault), 1_000_000e6);

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

        vm.prank(relayer);
        foreignController.takeFromSparkVault(address(sparkVault), rateLimitIncreaseInOneHour);

        testState.rateLimit -= rateLimitIncreaseInOneHour;  // Rate limit goes down
        testState.usdcAlm   += rateLimitIncreaseInOneHour;  // The almProxy receives the taken amount
        testState.usdcVault -= rateLimitIncreaseInOneHour;  // The vault's usdc balance decreases

        _assertTestState(testState);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.takeFromSparkVault(address(sparkVault), 1);
    }

    function testFuzz_takeFromSparkVault(uint256 depositAmount, uint256 takeAmount) external {
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(key, 10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);

        depositAmount = _bound(depositAmount, 1e18, 10_000_000_000e18);
        takeAmount    = _bound(depositAmount, 1e18, depositAmount);

        deal(address(usdcBase), address(user), depositAmount);
        vm.startPrank(user);
        usdcBase.approve(address(sparkVault), depositAmount);
        sparkVault.deposit(depositAmount, address(user));
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        10_000_000_000e18,
            usdcAlm:          0,
            usdcVault:        depositAmount,
            vaultTotalAssets: depositAmount,
            vaultTotalSupply: depositAmount
        });

        _assertTestState(testState);

        vm.prank(relayer);
        foreignController.takeFromSparkVault(address(sparkVault), takeAmount);

        testState.rateLimit -= takeAmount;  // Rate limit goes down
        testState.usdcAlm   += takeAmount;  // The almProxy receives the taken amount
        testState.usdcVault -= takeAmount;  // The vault's usdc balance decreases

        _assertTestState(testState);
    }

}

contract ForeignControllerTakeFromSparkVaultE2ETests is ForkTestBase {

    struct E2ETestState {
        uint256 takeRateLimit;
        uint256 transferRateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultAssetsOut;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    address morphoUsdcVault = Base.MORPHO_VAULT_SUSDC;

    bytes32 LIMIT_4626_DEPOSIT     = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 LIMIT_4626_WITHDRAW    = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 LIMIT_ASSET_TRANSFER   = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 LIMIT_SPARK_VAULT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 LIMIT_USDS_TO_USDC     = keccak256("LIMIT_USDS_TO_USDC");

    address user = makeAddr("user");

    bytes32 takeKey;
    bytes32 transferKey;

    SparkVault sparkVault;

    function setUp() public override {
        super.setUp();

        // Step 1: Deploy the spark vault

        sparkVault = SparkVault(
            address(new ERC1967Proxy(
                address(new SparkVault()),
                abi.encodeCall(
                    SparkVault.initialize,
                    (address(usdcBase), "Spark Savings USDC V2", "spUSDC", Base.SPARK_EXECUTOR)
                )
            ))
        );

        // Step 2 (spell): Grant roles to the almProxy and setter, set VSR bounds

        vm.startPrank(Base.SPARK_EXECUTOR);

        sparkVault.grantRole(sparkVault.TAKER_ROLE(),  address(almProxy));
        sparkVault.grantRole(sparkVault.SETTER_ROLE(), relayer);

        sparkVault.setVsrBounds(1e27, 1.000000003022265980097387650e27);  // 0% to 10% APY

        // Step 3 (spell): Set the rate limits

        takeKey = RateLimitHelpers.makeAddressKey(
            LIMIT_SPARK_VAULT_TAKE,
            address(sparkVault)
        );

        transferKey = RateLimitHelpers.makeAddressAddressKey(
            LIMIT_ASSET_TRANSFER,
            address(usdcBase),
            address(sparkVault)
        );

        bytes32 morphoKey = RateLimitHelpers.makeAddressKey(
            LIMIT_4626_DEPOSIT,
            address(morphoUsdcVault)
        );

        bytes32 morphoWithdrawKey = RateLimitHelpers.makeAddressKey(
            LIMIT_4626_WITHDRAW,
            address(morphoUsdcVault)
        );

        rateLimits.setRateLimitData(takeKey,            10_000_000e6, uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(transferKey,        10_000_000e6, uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(morphoKey,          10_000_000e6, uint256(10_000_000e6) / 1 days);
        rateLimits.setRateLimitData(LIMIT_USDS_TO_USDC, 10_000_000e6, uint256(10_000_000e6) / 1 days);

        rateLimits.setUnlimitedRateLimitData(morphoWithdrawKey);

        // Step 4 (spell): Set maxSlippage for ERC4626 deposit

        foreignController.setMaxSlippage(morphoUsdcVault, 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 34717833;  // August 26, 2025
    }

    function _assertE2EState(E2ETestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey),     state.takeRateLimit,     tolerance, "takeRateLimit");
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(transferKey), state.transferRateLimit, tolerance, "transferRateLimit");

        assertApproxEqAbs(usdcBase.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(usdcBase.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                state.vaultTotalSupply, tolerance, "vaultTotalSupply");
        assertApproxEqAbs(sparkVault.assetsOutstanding(),          state.vaultAssetsOut,   tolerance, "vaultAssetsOut");
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

        deal(address(usdcBase), address(user), 10_000_000e6);
        vm.startPrank(user);
        usdcBase.approve(address(sparkVault), 10_000_000e6);
        sparkVault.deposit(10_000_000e6, address(user));
        vm.stopPrank();

        testState.usdcVault        = 10_000_000e6;
        testState.vaultTotalAssets = 10_000_000e6;
        testState.vaultTotalSupply = 10_000_000e6;

        _assertE2EState(testState);

        skip(1 days);

        // Step 3: Take usdc from the spark vault

        vm.prank(relayer);
        foreignController.takeFromSparkVault(address(sparkVault), 9_000_000e6);

        testState.takeRateLimit  = 1_000_000e6;
        testState.usdcAlm        = 9_000_000e6;
        testState.usdcVault      = 1_000_000e6;
        testState.vaultAssetsOut = 9_000_000e6;

        _assertE2EState(testState);

        skip(10 days);  // Get full rate limit for Morpho deposit

        // Step 4: Deposit into Morpho and set the VSR to 4% APY

        vm.startPrank(relayer);
        uint256 shares = foreignController.depositERC4626(morphoUsdcVault, 9_000_000e6);
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

        vm.startPrank(relayer);
        uint256 assets = foreignController.redeemERC4626(morphoUsdcVault, shares);
        foreignController.transferAsset(address(usdcBase), address(sparkVault), 9_400_000e6);
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
        assertEq(usdcBase.balanceOf(user), 10_400_000e6 - 1);  // Rounding against user
    }

}
