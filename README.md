# Spark ALM Controller

![Foundry CI](https://github.com/marsfoundation/spark-alm-controller/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/marsfoundation/spark-alm-controller/blob/master/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

This repo contains the onchain components of the Spark Liquidity Layer. The following contracts are contained in this repository:

- `ALMProxy`: The proxy contract that holds custody of all funds. This contract routes calls to external contracts according to logic within a specified `controller` contract. This pattern was used to allow for future iterations in logic, as a new controller can be onboarded and can route calls through the proxy with new logic. This contract is stateless except for the ACL logic contained within the inherited OpenZeppelin `AccessControl` contract.
- `ForeignController`: This controller contract is intended to be used on "foreign" domains. The term "foreign" is used to describe a domain that is not the Ethereum mainnet.
- `MainnetController`: This controller contract is intended to be used on the Ethereum mainnet.
- `RateLimits`: This contract is used to enforce and update rate limits on logic in the `ForeignController` and `MainnetController` contracts. This contract is stateful and is used to store the rate limit data.

## Architecture

The general structure of calls is shown in the diagram below. The `controller` contract is the entry point for all calls. The `controller` contract checks the rate limits if necessary and executes the relevant logic. The `controller` can perform multiple calls to the `ALMProxy` contract atomically with specified calldata.

<p align="center">
  <img src="https://github.com/user-attachments/assets/832db958-14e6-482f-9dbc-b10e672029f7" alt="Image 1" height="700px" style="margin-right:100px;"/>
</p>

The diagram below provides and example of calling to mint USDS using the Sky allocation system. Note that the funds are always held custody in the `ALMProxy` as a result of the calls made.

<p align="center">
  <img src="https://github.com/user-attachments/assets/312634c3-0c3e-4f5a-b673-b44e07d3fb56" alt="Image 2" height="700px"/>
</p>

## Permissions

All contracts in this repo inherit and implement the AccessControl contract from OpenZeppelin to manage permissions. The following roles are defined:

- `DEFAULT_ADMIN_ROLE`: The admin role is the role that can grant and revoke roles. Also used for general admin functions in all contracts.
- `RELAYER`: Used for the ALM Planner offchain system. This address can call functions on `controller` contracts to perform actions on behalf of the `ALMProxy` contract.
- `FREEZER`: Allows an address with this role to remove a `RELAYER` that has been compromised. The intention of this is to have a backup `RELAYER` that the system can fall back to when the main one is removed.
- `CONTROLLER`: Used for the `ALMProxy` contract. Only contracts with this role can call the `call` functions on the `ALMProxy` contract. Also used in the RateLimits contract, only this role can update rate limits.

## Controller Functionality

The `MainnetController` contains all logic necessary to interact with the Sky allocation system to mint and burn USDS, swap USDS to USDC in the PSM, as well as interact with mainnet external protocols and CCTP for bridging USDC.
The `ForeignController` contains all logic necessary to deposit, withdraw, and swap assets in L2 PSMs as well as interact with external protocols on L2s and CCTP for bridging USDC.

## Rate Limits

The `RateLimits` contract is used to enforce rate limits on the `controller` contracts. The rate limits are defined using `keccak256` hashes to identify which function to apply the rate limit to. This was done to allow flexibility in future function signatures for the same desired high-level functionality. The rate limits are stored in a mapping with the `keccak256` hash as the key and a struct containing the rate limit data:

- `maxAmount`: Maximum allowed amount at any time.
- `slope`: The slope of the rate limit, used to calculate the new limit based on time passed. [tokens / second]
- `lastAmount`: The amount left available at the last update.
- `lastUpdated`: The timestamp when the rate limit was last updated.

The rate limit is calculated as follows:

<div align="center">

`currentRateLimit = min(slope * (block.timestamp - lastUpdated) + lastAmount, maxAmount)`

</div>

This is a linear rate limit that increases over time with a maximum limit. This rate limit is derived from these values which can be set by and admin OR updated by the `CONTROLLER` role. The `CONTROLLER` updates these values to increase/decrease the rate limit based on the functionality within the contract (e.g., decrease the rate limit after minting USDS by the minted amount by decrementing `lastAmount` and setting `lastUpdated` to `block.timestamp`).

## Rate Limit Uses

The current uses of rate limits can be seen in [`./printers/rate_limits.py`](./printers/rate_limits.py) (for both the Foreign and Mainnet controllers). The file is also an executable [Wake](https://github.com/Ackee-Blockchain/wake) printer, which can at any time check that the information in the file is correct. Wake can be installed for example with any of these:

```bash
uv tool install eth-wake
pipx install eth-wake
pip install eth-wake
```

Printers are scripts that you can run over the AST of the codebase. To execute this script, run:

```bash
❯ wake --config printers/wake.toml print rate-limits
[14:16:59] Found 16 *.sol files in 0.51 s                                                 print.py:466
           Loaded previous build in 0.47 s                                             compiler.py:862
           Compiled 0 files using 0 solc runs in 0.00 s                               compiler.py:1242
           Processed compilation results in 0.01 s                                    compiler.py:1495
📦 Checking MainnetController...
✅ Successfully checked MainnetController...
📦 Checking ForeignController...
✅ Successfully checked ForeignController...
```

(A zero exit-code indicates the spec is satisfied.)

If the `printers/wake.toml` config file ever goes out of sync, you can regenerate it by running

```bash
wake up config
```

This will read Foundry remappings and create a new `wake.toml` file (which can then be moved to /printers.)

# Offchain Swap Support

This allows the SLL to perform an offchain swap while ensuring some constraints on how much capital has left the system at a time. It is intended to be used to gain access to liquidity from sources such as OTC Desks and exchanges.

The idea is to have funds sent from the ALM Proxy to the offchain destination. This contract will not be able to send any more funds to an exchange until the required balance is returned. It can be thought of like a gating mechanism that only allows a maximum `X` of funds to be outside the system, per approved OTC exchange, at any time.

This will provide strong guarantees to Spark/Sky that at most `X` can be stolen/lost, per whitelisted OTC route, while still allowing for rapid throughput into an offchain market with high liquidity such as Binance. Below is a diagram outlining how the system works using Binance as an example.

![Offchain Swap Module](https://github.com/user-attachments/assets/9aed5b7f-0b6e-45e3-8ad8-10bc5016470d)

## OTC Swap Conditions

In order for an OTC swap to be performed `isOtcSwapReady(exchange)` must return `true`. This function has two main components:

### Slippage

`maxSlippages` mapped on `exchange`, used in the same way as other parts of the controller. This value calculates a minimum viable amount to be returned from a swap in order for it to be considered complete, so another can be performed.

### Recharge Rate

In the OTC struct, there is a value `rechargeRate` that is expressed in 18 decimals of token per second. This value increases over time after the initial swap is sent. This value is necessary in the case where the exchange does return a material amount of funds but it is below the configured `maxSlippage`. In order to prevent the configuration of the system from bricking swapping functionality, this mechanism allows the OTC swap returned amount to virtually "recharge" over time so that it will eventually get over the required amount.

The equation to determine if an OTC swap is ready is:

$$ claimedAmount + (blockTimestamp - sentTimestamp) \times rechargeRate \ge sentAmount \times maxSlippage $$

## Trust Assumptions and Attack Mitigation

Below are all stated trust assumptions for using this contract in production:

- The `DEFAULT_ADMIN_ROLE` is fully trusted, to be run by governance.
- The `RELAYER` role is assumed to be able to be fully compromised by a malicious actor. **This should be a major consideration during auditing engagements.**
  - The logic in the smart contracts must prevent the movement of value anywhere outside of the ALM system of contracts. The exception for this is in asynchronous style integrations such as BUIDL, where `transferAsset` can be used to send funds to a whitelisted address. LP tokens are then asynchronously minted into the ALMProxy in a separate transaction.
  - Any action must be limited to "reasonable" slippage/losses/opportunity cost by rate limits.
  - The `FREEZER` must be able to stop the compromised `RELAYER` from performing more harmful actions within the max rate limits by using the `removeRelayer` function.
- A compromised `RELAYER` can perform DOS attacks. These attacks along with their respective recovery procedures are outlined in the `Attacks.t.sol` test files.
- Ethena USDe Mint/Burn is trusted to not honor requests with over 50bps slippage from a delegated signer.
- Withdrawals using `withdrawERC4626`/`redeemERC4626`/`withdrawAave` must always have a non-zero deposit rate limit set for their corresponding deposit functions in order to succeed.
- All whitelisted exchanges or OTC desks have no counterparty risk (i.e. they will asynchronously complete the trade) outside of slippage risks.
- All assets are tracking the same underlying. In other words, there will only be USD stablecoins. The value of these assets are treated the same (i.e. 1 USDT = 1 USDC). No yield-bearing versions, just 1:1.
- Assume that the funds return to the OTC Buffer contract via transfer. This is to accommodate most exchanges/OTC desks that only have the ability to complete the swap by sending token to an address (i.e. not being able to make any arbitrary contracts calls outside of the ERC20 spec).
- The maximum loss by the protocol is limited to the single outstanding OTC swap amount for a given exchange.
- The recharge rate is configured to be low enough that the system will not practically allow for multiple swaps in a row without receiving material funds from the exchange.
- Ethena's delegated signer role can be set by the RELAYER. The delegated signer role can technically be set by a malicious relayer to be a malicious actor. Ethena's API's [Order Validity Checks](https://docs.ethena.fi/solution-design/minting-usde/order-validity-checks) is trusted to prevent attacks in this scenario.

## Operational Requirements

- All ERC-4626 vaults that are onboarded MUST have an initial burned shares amount that prevents rounding-based frontrunning attacks. These shares have to be unrecoverable so that they cannot be removed at a later date.
- All ERC-20 tokens are to be non-rebasing with sufficiently high decimal precision.
- Rate limits must be configured for specific ERC-4626 vaults and AAVE aTokens (vaults without rate limits set will revert). Unlimited rate limits can be used as an onboarding tool.
- All Uniswap V4 pool onboardings are to be done with 1:1 assets.
- Rate limits must take into account:
  - Risk tolerance for a given protocol
  - Griefing attacks (e.g., repetitive transactions with high slippage by malicious relayer).

## ALM Proxy Freezable

The [`ALMProxyFreezable.sol`](./src/ALMProxyFreezable.sol) contract is a variant of the `ALMProxy` that is not intended to hold funds or have any critical authority. Rather, it plays a role within the ALM ecosystem to define low-risk parameters.

A key architectural difference from the standard `ALMProxy` is how the `CONTROLLER` role is used. In the standard `ALMProxy`, the `controller` is a controller contract (e.g., `MainnetController` or `ForeignController`) that itself acts when approved relayers interact with it. In contrast, the "controllers" of the `ALMProxyFreezable` are the relayers themselves, since they are granted the `CONTROLLER` role directly.

Since relayers are not necessarily first-party accounts or governance entities, they still carry some risk of misbehaving. To mitigate this risk, the `FREEZER` role has the additional ability to remove controllers via the `removeController` function in `ALMProxyFreezable`, which does not exist in the `ALMProxy`. This provides a safety mechanism to quickly revoke access from any relayer that may be compromised or acting maliciously, without needing to involve the same slower governance process that is used to remove the controller of the `ALMProxy`.

## Testing

To run all tests, run the following command:

```bash
forge test
```

## Deployments

All commands to deploy:

- Either the full system or just the controller
- To mainnet or base
- For staging or production

Can be found in the Makefile, with the nomenclature `make deploy-<domain>-<env>-<type>`.

Deploy a full ALM system to base production: `make deploy-base-production-full`
Deploy a controller to mainnet production: `make deploy-mainnet-production-controller`

To deploy a full staging environment from scratch, with a new allocation system and all necessary dependencies, run `make deploy-staging-full`.

## Upgrade Simulations

To perform upgrades against forks of mainnet and base for testing/simulation purposes, use the following instructions.

1. Set up two anvil nodes forked against mainnet and base.

```
anvil --fork-url $MAINNET_RPC_URL
```

```
anvil --fork-url $BASE_RPC_URL -p 8546
```

```
anvil --fork-url $ARBITRUM_ONE_RPC_URL -p 8547
```

2. Point to local RPCs.

```
export MAINNET_RPC_URL=http://127.0.0.1:8545
export BASE_RPC_URL=http://127.0.0.1:8546
export ARBITRUM_ONE_RPC_URL=http://127.0.0.1:8547
```

3. Upgrade mainnet contracts impersonating as the `SPARK_PROXY`.

```
export SPARK_PROXY=0x3300f198988e4C9C63F75dF86De36421f06af8c4

cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_setBalance $SPARK_PROXY `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_impersonateAccount $SPARK_PROXY

ENV=production \
OLD_CONTROLLER=0xb960F71ca3f1f57799F6e14501607f64f9B36F11 \
NEW_CONTROLLER=0x5cf73FDb7057E436A6eEaDFAd27E45E7ab6E431e \
forge script script/Upgrade.s.sol:UpgradeMainnetController --broadcast --unlocked --sender $SPARK_PROXY
```

4. Upgrade base contracts impersonating as the `SPARK_EXEUCTOR`.

```
export SPARK_EXECUTOR=0xF93B7122450A50AF3e5A76E1d546e95Ac1d0F579

cast rpc --rpc-url="$BASE_RPC_URL" anvil_setBalance $SPARK_EXECUTOR `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$BASE_RPC_URL" anvil_impersonateAccount $SPARK_EXECUTOR

CHAIN=base \
ENV=production \
OLD_CONTROLLER=0xc07f705D0C0e9F8C79C5fbb748aC1246BBCC37Ba \
NEW_CONTROLLER=0x5F032555353f3A1D16aA6A4ADE0B35b369da0440 \
forge script script/Upgrade.s.sol:UpgradeForeignController --broadcast --unlocked --sender $SPARK_EXECUTOR
```
