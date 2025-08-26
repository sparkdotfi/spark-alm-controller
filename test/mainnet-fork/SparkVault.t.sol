// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock as MockERC20 } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }           from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { SparkVault } from "spark-vaults-v2/src/SparkVault.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerTakeFromSparkVaultTestBase is ForkTestBase {

    struct UnitTestState {
        uint256 rateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    struct E2ETestState {
        uint256 takeRateLimit;
        uint256 transferRateLimit;
        uint256 usdcAlm;
        uint256 usdcVault;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    bytes32 LIMIT_ASSET_TRANSFER   = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 LIMIT_SPARK_VAULT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    SparkVault sparkVault;

    address admin  = makeAddr("admin");
    address setter = makeAddr("setter");
    address user   = makeAddr("user");

    bytes32 takeKey;
    bytes32 transferKey;

    function setUp() public override {
        super.setUp();

        sparkVault = SparkVault(
            address(new ERC1967Proxy(
                address(new SparkVault()),
                abi.encodeCall(
                    SparkVault.initialize,
                    (address(usdc), "Spark Savings USDC V2", "spUSDC", admin)
                )
            ))
        );

        vm.startPrank(admin);
        sparkVault.grantRole(sparkVault.TAKER_ROLE(),  address(almProxy));
        sparkVault.grantRole(sparkVault.SETTER_ROLE(), address(setter));
        vm.stopPrank();

        takeKey = RateLimitHelpers.makeAssetKey(
            LIMIT_SPARK_VAULT_TAKE,
            address(sparkVault)
        );

        transferKey = RateLimitHelpers.makeAssetDestinationKey(
            LIMIT_ASSET_TRANSFER,
            address(usdc),
            address(sparkVault)
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey,     1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(transferKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);
        vm.stopPrank();
    }

    function _assertUnitTestState(UnitTestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey), state.rateLimit,        tolerance, "rateLimit");
        assertApproxEqAbs(usdc.balanceOf(address(almProxy)),       state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(usdc.balanceOf(address(sparkVault)),     state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),                state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),                state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertE2EState(E2ETestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(takeKey),      state.takeRateLimit,     tolerance, "takeRateLimit");
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(transferKey), state.transferRateLimit, tolerance, "transferRateLimit");

        assertApproxEqAbs(usdc.balanceOf(address(almProxy)),   state.usdcAlm,          tolerance, "usdcAlm");
        assertApproxEqAbs(usdc.balanceOf(address(sparkVault)), state.usdcVault,        tolerance, "usdcVault");
        assertApproxEqAbs(sparkVault.totalAssets(),            state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),            state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertUnitTestState(UnitTestState memory state) internal view {
        _assertUnitTestState(state, 0);
    }

    function _assertE2EState(E2ETestState memory state) internal view {
        _assertE2EState(state, 0);
    }

}

contract MainnetControllerTakeFromSparkVaultFailureTests is MainnetControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(address(usdc), address(user), 10_000_000e18);
        vm.startPrank(user);
        usdc.approve(address(sparkVault), 10_000_000e18);
        sparkVault.deposit(10_000_000e18, address(user));
        vm.stopPrank();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18);
    }

}

contract MainnetControllerTakeFromSparkVaultTests is MainnetControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_rateLimited() external {
        deal(address(usdc), address(user), 10_000_000e18);
        vm.startPrank(user);
        usdc.approve(address(sparkVault), 10_000_000e18);
        sparkVault.deposit(10_000_000e18, address(user));
        vm.stopPrank();

        UnitTestState memory testState = UnitTestState({
            rateLimit:        1_000_000e18,
            usdcAlm:          0,
            usdcVault:        10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        });

        _assertUnitTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), 1_000_000e18);

        testState.rateLimit -= 1_000_000e18;  // Rate limit goes down
        testState.usdcAlm   += 1_000_000e18;  // The almProxy receives the taken amount
        testState.usdcVault -= 1_000_000e18;  // The vault's usdc balance decreases

        _assertUnitTestState(testState);

        skip(1 hours);

        // 1/24th of the rate limit per hour
        uint256 rateLimitIncreaseInOneHour = uint256(1_000_000e18) / (1 days) * (1 hours);
        assertEq(rateLimitIncreaseInOneHour, 41666.666666666666666400e18);

        testState.rateLimit += rateLimitIncreaseInOneHour;

        _assertUnitTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), rateLimitIncreaseInOneHour);

        testState.rateLimit -= rateLimitIncreaseInOneHour;  // Rate limit goes down
        testState.usdcAlm   += rateLimitIncreaseInOneHour;  // The almProxy receives the taken amount
        testState.usdcVault -= rateLimitIncreaseInOneHour;  // The vault's usdc balance decreases

        _assertUnitTestState(testState);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 1);
    }

    function testFuzz_takeFromSparkVault(uint256 depositAmount, uint256 takeAmount) external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(takeKey,     10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);
        rateLimits.setRateLimitData(transferKey, 10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);
        vm.stopPrank();

        depositAmount = _bound(depositAmount, 1e18, 10_000_000_000e18);
        takeAmount    = _bound(depositAmount, 1e18, depositAmount);

        deal(address(usdc), address(user), depositAmount);
        vm.startPrank(user);
        usdc.approve(address(sparkVault), depositAmount);
        sparkVault.deposit(depositAmount, address(user));
        vm.stopPrank();

        UnitTestState memory testState = UnitTestState({
            rateLimit:        10_000_000_000e18,
            usdcAlm:          0,
            usdcVault:        depositAmount,
            vaultTotalAssets: depositAmount,
            vaultTotalSupply: depositAmount
        });

        _assertUnitTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), takeAmount);

        testState.rateLimit -= takeAmount;  // Rate limit goes down
        testState.usdcAlm   += takeAmount;  // The almProxy receives the taken amount
        testState.usdcVault -= takeAmount;  // The vault's usdc balance decreases

        _assertUnitTestState(testState);
    }

}

contract MainnetControllerTakeFromSparkVaultE2ETests is MainnetControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_e2e() external {
        deal(address(usdc), address(user), 10_000_000e18);
        vm.startPrank(user);
        usdc.approve(address(sparkVault), 10_000_000e18);
        sparkVault.deposit(10_000_000e18, address(user));
        vm.stopPrank();
    }

}
