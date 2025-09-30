// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library LimitsLib {

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_4626_DEPOSIT         = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant LIMIT_4626_WITHDRAW        = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public constant LIMIT_7540_DEPOSIT         = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant LIMIT_7540_REDEEM          = keccak256("LIMIT_7540_REDEEM");
    bytes32 public constant LIMIT_AAVE_DEPOSIT         = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant LIMIT_AAVE_WITHDRAW        = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public constant LIMIT_ASSET_TRANSFER       = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public constant LIMIT_CURVE_DEPOSIT        = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant LIMIT_CURVE_SWAP           = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant LIMIT_CURVE_WITHDRAW       = keccak256("LIMIT_CURVE_WITHDRAW");
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER   = keccak256("LIMIT_LAYERZERO_TRANSFER");
    bytes32 public constant LIMIT_MAPLE_REDEEM         = keccak256("LIMIT_MAPLE_REDEEM");
    bytes32 public constant LIMIT_FARM_DEPOSIT         = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public constant LIMIT_FARM_WITHDRAW        = keccak256("LIMIT_FARM_WITHDRAW");
    bytes32 public constant LIMIT_SPARK_VAULT_TAKE     = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 public constant LIMIT_SUPERSTATE_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");
    bytes32 public constant LIMIT_SUSDE_COOLDOWN       = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 public constant LIMIT_USDC_TO_CCTP         = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_USDC_TO_DOMAIN       = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 public constant LIMIT_USDE_BURN            = keccak256("LIMIT_USDE_BURN");
    bytes32 public constant LIMIT_USDE_MINT            = keccak256("LIMIT_USDE_MINT");
    bytes32 public constant LIMIT_USDS_MINT            = keccak256("LIMIT_USDS_MINT");
    bytes32 public constant LIMIT_USDS_TO_USDC         = keccak256("LIMIT_USDS_TO_USDC");

}
