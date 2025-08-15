// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock as MockERC20 } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { ERC1967Proxy }           from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Todo: Renme to SparkVault upstream:
import { Vault as SparkVault } from "spark-vaults-v2/src/Vault.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerTakeFromSparkVaultTestBase is ForkTestBase {

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
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.takeFromSparkVault(address(sparkVault), 1e18);
    }

    function test_takeFromSparkVault_rateLimitBoundary() external {
        deal(address(asset), address(this), 10_000_000e18);
        asset.approve(address(sparkVault), 10_000_000e18);
        sparkVault.mint(10_000_000e18, address(this));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
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

        vm.startPrank(relayer);
        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);
        assertEq(asset.balanceOf(address(almProxy)), 0);
        mainnetController.takeFromSparkVault(address(sparkVault), 1_000_000e18);
        assertEq(asset.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 41666.666666666666666400e18);
        assertEq(asset.balanceOf(address(almProxy)), 1_000_000e18);
        mainnetController.takeFromSparkVault(address(sparkVault), 41666.666666666666666400e18);
        assertEq(asset.balanceOf(address(almProxy)), 1_041_666.666666666666666400e18);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.takeFromSparkVault(address(sparkVault), 1);

        vm.stopPrank();
    }

}
