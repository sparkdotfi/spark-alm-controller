// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock as MockERC20 } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }           from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { SparkVault } from "spark-vaults-v2/src/SparkVault.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerTakeFromSparkVaultTestBase is ForkTestBase {

    struct TestState {
        uint256 rateLimit;
        uint256 assetAlm;
        uint256 assetVault;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    bytes32 LIMIT_SPARK_VAULT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    // TODO: Use a real on-chain contract.
    // NOTE: The mock asset has 18 decimals.
    MockERC20  asset;
    SparkVault sparkVault;

    address admin  = makeAddr("admin");
    address setter = makeAddr("setter");
    address user   = makeAddr("user");

    bytes32 key;

    function setUp() public override {
        super.setUp();

        asset = new MockERC20();

        sparkVault = SparkVault(
            address(new ERC1967Proxy(
                address(new SparkVault()),
                abi.encodeCall(
                    SparkVault.initialize,
                    (address(asset), "Spark Savings USDC V2", "spUSDC", admin)
                )
            ))
        );

        vm.startPrank(admin);
        sparkVault.grantRole(sparkVault.TAKER_ROLE(), address(almProxy));
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            LIMIT_SPARK_VAULT_TAKE,
            address(sparkVault)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);
    }

    function _assertTestState(TestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(key),  state.rateLimit,        tolerance, "rateLimit");
        assertApproxEqAbs(asset.balanceOf(address(almProxy)),   state.assetAlm,         tolerance, "assetAlm");
        assertApproxEqAbs(asset.balanceOf(address(sparkVault)), state.assetVault,       tolerance, "assetVault");
        assertApproxEqAbs(sparkVault.totalAssets(),             state.vaultTotalAssets, tolerance, "vaultTotalAssets");
        assertApproxEqAbs(sparkVault.totalSupply(),             state.vaultTotalSupply, tolerance, "vaultTotalSupply");
    }

    function _assertTestState(TestState memory state) internal view {
        _assertTestState(state, 0);
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
        rateLimits.setRateLimitData(key, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(address(asset), address(user), 10_000_000e18);
        vm.startPrank(user);
        asset.approve(address(sparkVault), 10_000_000e18);
        sparkVault.deposit(10_000_000e18, address(user));
        vm.stopPrank();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18);
    }

}

contract MainnetControllerTakeFromSparkVaultTests is MainnetControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_rateLimited() external {
        deal(address(asset), address(user), 10_000_000e18);
        vm.startPrank(user);
        asset.approve(address(sparkVault), 10_000_000e18);
        sparkVault.deposit(10_000_000e18, address(user));
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        1_000_000e18,
            assetAlm:         0,
            assetVault:       10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        });

        _assertTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), 1_000_000e18);

        testState.rateLimit  -= 1_000_000e18;  // Rate limit goes down
        testState.assetAlm   += 1_000_000e18;  // The almProxy receives the taken amount
        testState.assetVault -= 1_000_000e18;  // The vault's asset balance decreases

        _assertTestState(testState);

        skip(1 hours);

        // 1/24th of the rate limit per hour
        uint256 rateLimitIncreaseInOneHour = uint256(1_000_000e18) / (1 days) * (1 hours);
        assertEq(rateLimitIncreaseInOneHour, 41666.666666666666666400e18);

        testState.rateLimit += rateLimitIncreaseInOneHour;

        _assertTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), rateLimitIncreaseInOneHour);

        testState.rateLimit  -= rateLimitIncreaseInOneHour;  // Rate limit goes down
        testState.assetAlm   += rateLimitIncreaseInOneHour;  // The almProxy receives the taken amount
        testState.assetVault -= rateLimitIncreaseInOneHour;  // The vault's asset balance decreases

        _assertTestState(testState);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 1);
    }

    function testFuzz_takeFromSparkVault(uint256 depositAmount, uint256 takeAmount) external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000_000e18, uint256(10_000_000_000e18) / 1 days);

        depositAmount = _bound(depositAmount, 1e18, 10_000_000_000e18);
        takeAmount    = _bound(depositAmount, 1e18, depositAmount);

        deal(address(asset), address(user), depositAmount);
        vm.startPrank(user);
        asset.approve(address(sparkVault), depositAmount);
        sparkVault.deposit(depositAmount, address(user));
        vm.stopPrank();

        TestState memory testState = TestState({
            rateLimit:        10_000_000_000e18,
            assetAlm:         0,
            assetVault:       depositAmount,
            vaultTotalAssets: depositAmount,
            vaultTotalSupply: depositAmount
        });

        _assertTestState(testState);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), takeAmount);

        testState.rateLimit  -= takeAmount;  // Rate limit goes down
        testState.assetAlm   += takeAmount;  // The almProxy receives the taken amount
        testState.assetVault -= takeAmount;  // The vault's asset balance decreases

        _assertTestState(testState);
    }

}

