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

        key = RateLimitHelpers.makeAssetKey(
            LIMIT_SPARK_VAULT_TAKE,
            address(asset)
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

}

