// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock as MockERC20 } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }           from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Todo: Renme to SparkVault upstream:
import { Vault as SparkVault } from "spark-vaults-v2/src/Vault.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerTakeFromSparkVaultTestBase is ForkTestBase {
    struct TestState {
        uint256 rateLimit;
        uint256 assetThis;
        uint256 assetAlm;
        uint256 assetVault;
        uint256 vaultThis;
        uint256 vaultTotalAssets;
        uint256 vaultTotalSupply;
    }

    bytes32 LIMIT_SPARK_VAULT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    // Todo: Use a real on-chain contract.
    // Note: Our mock asset has 18 decimals.
    MockERC20  asset;
    SparkVault sparkVault;

    address admin  = makeAddr("admin");
    address setter = makeAddr("setter");

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

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);
        vm.stopPrank();
    }
    function _assertTestState(TestState memory state, uint256 tolerance) internal view {
        assertApproxEqAbs(
            rateLimits.getCurrentRateLimit(key), state.rateLimit, tolerance, "rateLimit"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(this)), state.assetThis, tolerance, "assetThis"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(almProxy)), state.assetAlm, tolerance, "assetAlm"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(sparkVault)), state.assetVault, tolerance, "assetVault"
        );
        assertApproxEqAbs(
            sparkVault.balanceOf(address(this)), state.vaultThis, tolerance, "vaultThis"
        );
        assertApproxEqAbs(
            sparkVault.totalAssets(), state.vaultTotalAssets, tolerance, "vaultTotalAssets"
        );
        assertApproxEqAbs(
            sparkVault.totalSupply(), state.vaultTotalSupply,  tolerance, "vaultTotalSupply"
        );
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
        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);
        vm.stopPrank();

        // >> Prank
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(address(asset), address(this), 10_000_000e18);
        asset.approve(address(sparkVault), 10_000_000e18);
        sparkVault.mint(10_000_000e18, address(this));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);
        vm.stopPrank();

        // >> Prank
        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18 + 1);

        vm.prank(relayer);
        mainnetController.takeFromSparkVault(address(sparkVault), 10_000_000e18);
    }

}

contract MainnetControllerTakeFromSparkVaultTests is MainnetControllerTakeFromSparkVaultTestBase {

    function test_takeFromSparkVault_rateLimited() external {
        deal(address(asset), address(this), 10_000_000e18);
        asset.approve(address(sparkVault), 10_000_000e18);
        sparkVault.mint(10_000_000e18, address(this));

        // >> start Prank
        vm.startPrank(relayer);

        _assertTestState(TestState({
            rateLimit: 1_000_000e18,
            assetThis: 0,
            assetAlm: 0,
            assetVault: 10_000_000e18,
            vaultThis: 10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        }));

        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), 1_000_000e18);

        _assertTestState(TestState({
            rateLimit: 0,
            assetThis: 0,
            assetAlm: 1_000_000e18,
            assetVault: 9_000_000e18,
            vaultThis: 10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        }));

        skip(1 hours);

        _assertTestState(TestState({
            rateLimit: 41666.666666666666666400e18,
            assetThis: 0,
            assetAlm: 1_000_000e18,
            assetVault: 9_000_000e18,
            vaultThis: 10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        }));

        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), 41666.666666666666666400e18);

        _assertTestState(TestState({
            rateLimit: 0,
            assetThis: 0,
            assetAlm: 1_041_666.666666666666666400e18,
            assetVault: 8_958_333.333333333333333600e18,
            vaultThis: 10_000_000e18,
            vaultTotalAssets: 10_000_000e18,
            vaultTotalSupply: 10_000_000e18
        }));

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 1);

        vm.stopPrank();
    }

    function testFuzz_takeFromSparkVault(uint256 mintAmount, uint256 takeAmount) external {
        mintAmount = _bound(mintAmount, 1e18, 1_000_000e18);
        takeAmount = _bound(mintAmount, 1e18, mintAmount);

        deal(address(asset), address(this), mintAmount);
        asset.approve(address(sparkVault), mintAmount);
        sparkVault.mint(mintAmount, address(this));

        // >> start Prank
        vm.startPrank(relayer);
        _assertTestState(TestState({
            rateLimit: 1_000_000e18,
            assetThis: 0,
            assetAlm: 0,
            assetVault: mintAmount,
            vaultThis: mintAmount,
            vaultTotalAssets: mintAmount,
            vaultTotalSupply: mintAmount
        }));

        // >> Action
        mainnetController.takeFromSparkVault(address(sparkVault), takeAmount);

        _assertTestState(TestState({
            // Rate limit goes down
            rateLimit: 1_000_000e18 - takeAmount,
            // LPs' asset balance don't change
            assetThis: 0,
            // The almProxy receives the taken amount
            assetAlm: takeAmount,
            // The vault's asset balance decreases
            assetVault: mintAmount - takeAmount,
            // LPs' balances don't change
            vaultThis: mintAmount,
            // totalAssets don't decrease
            vaultTotalAssets: mintAmount,
            // totalSupply doesn't decrease
            vaultTotalSupply: mintAmount
        }));
    }

}
