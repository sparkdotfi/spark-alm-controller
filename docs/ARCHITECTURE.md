# Architecture

This document describes the architecture of the Spark ALM Controller system.

## Core Contracts

### ALMProxy

The proxy contract that holds custody of all funds. This contract routes calls to external contracts according to logic within a specified `controller` contract.

**Key characteristics:**
- Stateless except for ACL logic (OpenZeppelin `AccessControl`)
- Allows future iterations in logic by onboarding new controllers
- New controllers can route calls through the proxy with new logic

### Controllers

#### MainnetController

Controller contract intended for use on Ethereum mainnet.

**Capabilities:**
- Interact with the Sky allocation system to mint and burn USDS
- Swap USDS to USDC in the PSM
- Interact with mainnet external protocols
- Bridge USDC via CCTP and OFTs with LayerZero

#### ForeignController

Controller contract intended for use on "foreign" domains (any domain that is not Ethereum mainnet).

**Capabilities:**
- Deposit, withdraw, and swap assets in L2 PSMs
- Interact with external protocols on L2s
- Bridge USDC via CCTP and OFTs with LayerZero

### RateLimits

Contract used to enforce and update rate limits on the controller contracts.

**Key characteristics:**
- Stateful contract storing rate limit data
- Uses `keccak256` hashes to identify functions for rate limiting
- Allows flexibility in future function signatures while maintaining the same high-level functionality

See [RATE_LIMITS.md](./RATE_LIMITS.md) for detailed rate limit documentation.

### ALMProxyFreezable

A variant of the `ALMProxy` that is not intended to hold funds or have critical authority. It defines low-risk parameters within the ALM ecosystem.

**Architectural differences from standard ALMProxy:**
- **Controller role usage:** In the standard `ALMProxy`, the controller is a controller contract (e.g., `MainnetController`) that acts when approved relayers interact with it. In `ALMProxyFreezable`, the "controllers" are the relayers themselves (granted the `CONTROLLER` role directly).
- **Additional safety mechanism:** The `FREEZER` role can remove controllers via `removeController`, providing quick revocation of access from compromised or malicious relayers without slower governance processes.

### OTCBuffer

Buffer contract used for OTC swap operations. See [OTC_SWAPS.md](./OTC_SWAPS.md) for details.

### WEETHModule

Module contract used for facilitating NFT-based WEETH withdrawals. See [WEETH_INTEGRATION.md](./WEETH_INTEGRATION.md) for details.

## Architecture Diagrams

### General Call Flow

The general structure of calls is shown below. The `controller` contract is the entry point for all calls. It checks rate limits if necessary and executes the relevant logic. The controller can perform multiple calls to the `ALMProxy` contract atomically with specified calldata.

<p align="center">
  <img src="https://github.com/user-attachments/assets/832db958-14e6-482f-9dbc-b10e672029f7" alt="Call Flow Architecture" height="700px" style="margin-right:100px;"/>
</p>

### Example: Minting USDS

The diagram below provides an example of calling to mint USDS using the Sky allocation system. Note that funds are always held in custody by the `ALMProxy` as a result of the calls made.

<p align="center">
  <img src="https://github.com/user-attachments/assets/312634c3-0c3e-4f5a-b673-b44e07d3fb56" alt="USDS Minting Flow" height="700px"/>
</p>

## Permissions

All contracts in this repo inherit and implement the `AccessControl` contract from OpenZeppelin to manage permissions. The following roles are defined:

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Admin role that can grant and revoke roles. Also used for general admin functions in all contracts. |
| `RELAYER` | Used for the ALM Planner offchain system. Can call functions on controller contracts to perform actions on behalf of the `ALMProxy`. |
| `FREEZER` | Allows removal of a compromised `RELAYER`. Intended for use with a backup relayer that the system can fall back to. |
| `CONTROLLER` | Used for the `ALMProxy` contract. Only contracts with this role can call the `call` functions on `ALMProxy`. Also used in `RateLimits` contract for updating rate limits. |

## Contract Interactions

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│     Relayer     │────▶│  MainnetController   │────▶│    ALMProxy     │
│   (External)    │     │  or ForeignController│     │ (Funds Custody) │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
                                   │                          │
                                   │                          │
                                   ▼                          ▼
                        ┌──────────────────┐       ┌────────────────────┐
                        │   RateLimits     │       │ External Protocols │
                        │   (State Store)  │       │  (Sky, PSM, etc.)  │
                        └──────────────────┘       └────────────────────┘
```

## Libraries

The system uses several libraries for protocol integrations:

| Library | Purpose |
|---------|---------|
| `AaveLib` | AAVE protocol interactions |
| `ApproveLib` | Token approval utilities |
| `CCTPLib` | Circle CCTP bridging |
| `CurveLib` | Curve pool operations |
| `ERC4626Lib` | ERC-4626 vault interactions |
| `LayerZeroLib` | LayerZero cross-chain messaging |
| `PSMLib` | PSM (Peg Stability Module) operations |
| `UniswapV4Lib` | Uniswap V4 integrations |
| `WEETHLib` | weETH (wrapped eETH) operations |
