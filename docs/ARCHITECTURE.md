# Architecture

This document describes the architecture of the PAU system.

## Core Contracts

### ALMProxy

The proxy contract that holds custody of all funds. This contract routes calls to external contracts according to logic within a specified `controller` contract.

**Key characteristics:**
- Stateless except for ACL logic (OpenZeppelin `AccessControl`)
- Allows future iterations in logic by onboarding new controllers
- New controllers can route calls through the proxy with new logic

### Controller

The unified controller contract that serves as the entry point for all relayer operations. Inspired by the [EIP-2535 Diamond Proxy](https://eips.ethereum.org/EIPS/eip-2535) pattern, the Controller uses dispatch-based routing to delegate calls to specialized facets. Rather than maintaining separate controllers per domain (e.g., mainnet vs L2), a single Controller is deployed on each chain and configured with only the facets relevant to that deployment.

**Key characteristics:**
- Dispatch-based call routing: admin maps call selectors to (facet address, delegate selector) pairs via `setDispatch`
- Each facet uses its own ERC-7201 namespaced storage domain, preventing storage collisions
- Shared state (access controls, proxy, rate limits) is accessible to all facets via `ControllerSharedStorage`
- Reentrancy protection across all facet calls

**Capabilities (determined by which facets are wired):**
- Interact with the Sky allocation system to mint and burn USDS
- Swap USDS to USDC in the PSM
- Deposit, withdraw, and swap assets in L2 PSMs
- Interact with external protocols (Aave, ERC-4626 vaults, Curve, Uniswap, etc.)
- Bridge USDC via CCTP and OFTs with LayerZero
- Transfer shares via Centrifuge cross-chain

### RateLimits

Contract used to enforce and update rate limits on the Controller.

**Key characteristics:**
- Stateful contract storing rate limit data
- Uses `keccak256` hashes to identify functions for rate limiting
- Allows flexibility in future function signatures while maintaining the same high-level functionality

See [RATE_LIMITS.md](./RATE_LIMITS.md) for detailed rate limit documentation.

### ALMProxyFreezable

A variant of the `ALMProxy` that is not intended to hold funds or have critical authority. It defines low-risk parameters within the PAU ecosystem.

**Architectural differences from standard ALMProxy:**
- **Controller role usage:** In the standard `ALMProxy`, the controller is the `Controller` contract that acts when approved relayers interact with it. In `ALMProxyFreezable`, the "controllers" are the relayers themselves (granted the `CONTROLLER` role directly).
- **Additional safety mechanism:** The `FREEZER` role can remove controllers via `removeController`, providing quick revocation of access from compromised or malicious relayers without slower governance processes.

### OTCBuffer

Buffer contract used for OTC swap operations. See [LIQUIDITY_OPERATIONS.md](./LIQUIDITY_OPERATIONS.md#otc-buffer-configuration) for details.

### WEETHModule

Module contract used for facilitating NFT-based WEETH withdrawals. See [WEETH_INTEGRATION.md](./WEETH_INTEGRATION.md) for details.

## Architecture Diagrams

### General Call Flow

The general structure of calls is shown below. The `Controller` is the entry point for all calls. It dispatches to the appropriate facet, which checks rate limits if necessary and executes the relevant logic. Facets perform calls to the `ALMProxy` contract atomically with specified calldata.

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
| `RELAYER` | Used for the offchain relayer system. Can call functions on controller contracts to perform actions on behalf of the `ALMProxy`. |
| `FREEZER` | Allows removal of a compromised `RELAYER`. Intended for use with a backup relayer that the system can fall back to. |
| `CONTROLLER` | Used for the `ALMProxy` contract. Only the `Controller` with this role can call the `call` functions on `ALMProxy`. Also used in `RateLimits` contract for updating rate limits. |

## Contract Interactions

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│     Relayer     │────▶│   Controller     │────▶│    ALMProxy     │
│   (External)    │     │  (Dispatches to  │     │ (Funds Custody) │
└─────────────────┘     │    Facets)       │     └─────────────────┘
                        └──────────────────┘              │
                                   │                      │
                                   │                      │
                                   ▼                      ▼
                        ┌──────────────────┐    ┌────────────────────┐
                        │   RateLimits     │    │ External Protocols │
                        │   (State Store)  │    │  (Sky, PSM, etc.)  │
                        └──────────────────┘    └────────────────────┘
```

## Facets

The system uses a facet-based architecture where each protocol integration is encapsulated in its own facet. Each facet has its own ERC-7201 namespaced storage domain and is wired to the Controller via dispatch configuration. Which facets are active depends on the deployment (e.g., a mainnet deployment may have different facets than an L2 deployment).

| Facet | Purpose |
|-------|---------|
| `AaveFacet` | Aave protocol deposit/withdraw |
| `CCTPFacet` | Circle CCTP v2 USDC bridging |
| `CentrifugeFacet` | Centrifuge async vault (ERC-7887) interactions |
| `CurveFacet` | Curve StableSwap pool operations |
| `DAIUSDSFacet` | DAI to USDS conversion |
| `ERC4626Facet` | ERC-4626 vault deposit/withdraw |
| `ERC7540Facet` | ERC-7540 async vault interactions |
| `FarmFacet` | SPK farming deposit/withdraw |
| `LayerZeroFacet` | LayerZero v2 cross-chain messaging |
| `MapleFacet` | Maple token redemptions |
| `MerklFacet` | Merkl operator toggles |
| `OTCFacet` | Over-the-counter swap buffering |
| `PendleFacet` | Pendle PT redemptions |
| `PSMFacet` | Mainnet PSM USDS/USDC swaps |
| `PSM3Facet` | PSM3 deposit/withdraw |
| `SparkVaultFacet` | Spark Vault asset withdrawals |
| `SuperstateFacet` | Superstate USTB subscriptions |
| `TransferAssetFacet` | Generic ERC-20 transfers |
| `UniswapV3Facet` | Uniswap V3 positions and swaps |
| `UniswapV4Facet` | Uniswap V4 positions and swaps |
| `USDEFacet` | Ethena USDe/sUSDe operations |
| `USDSFacet` | USDS minting/burning via vault |
| `WEETHFacet` | EtherFi weETH/eETH operations |
| `WrapProxyETHFacet` | WETH wrapping utility |
| `WSTETHFacet` | Lido wstETH deposit/withdraw |
