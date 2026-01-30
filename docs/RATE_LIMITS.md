# Rate Limits

This document describes the rate limiting system used in the Spark ALM Controller.

## Overview

The `RateLimits` contract enforces rate limits on the controller contracts. Rate limits are keyed by individual `bytes32` hashes derived from a `bytes32` identifier unique to the integration and function, and optionally some data unique to the recipient, assets, pool, etc to apply the rate limit to. This design allows flexibility in future function signatures while maintaining the same high-level functionality.

### Whitelisting via Rate Limit Keys

Rate limit keys are constructed by hashing together a **function identifier** and an **address or ID** (e.g., pool address, vault address, token address). This mechanism serves as an implicit **whitelist/onboarding system**:

- **Examples:**
  - Depositing liquidity to a specific Uniswap V4 pool requires the rate limit key `keccak256(abi.encode(LIMIT_UNISWAP_V4_DEPOSIT, poolId))` to be set
  - Withdrawing an aToken from Aave requires the rate limit key `keccak256(abi.encode(LIMIT_AAVE_WITHDRAW, aToken))` to be set
  - Preparing a USDe burn requires the rate limit key `LIMIT_SUSDE_COOLDOWN` to be set
- **Security benefit:** Prevents relayers from interacting with arbitrary/malicious contracts - only governance-approved integrations have valid rate limit keys
- **Operational benefit:** New integrations can be onboarded with lower rate limits to ease into use, and then increased to manage ongoing risk/exposure, and providing a clear audit trail

See `RateLimitHelpers.sol` for the key generation utilities (e.g., `makeAddressKey`).

## Rate Limit Data Structure

Rate limits are stored in a mapping with the `keccak256` hash as the key and a struct containing:

| Field | Description |
|-------|-------------|
| `maxAmount` | Maximum allowed amount at any time |
| `slope` | Rate at which the limit increases [tokens / second] |
| `lastAmount` | Amount left available at the last update |
| `lastUpdated` | Timestamp when the rate limit was last updated |

## Rate Limit Calculation

The current rate limit is calculated as:

```
currentRateLimit = min(slope * (block.timestamp - lastUpdated) + lastAmount, maxAmount)
```

This is a **linear rate limit** that increases over time with a maximum limit.

### Update Mechanism

Rate limit values can be:
- **Set by an admin** - Direct configuration
- **Updated by the `CONTROLLER` role** - Automatic adjustment based on operations

For example, after minting USDS:
- `lastAmount` is decremented by the minted amount
- `lastUpdated` is set to `block.timestamp`

---

## Rate Limit Design Decisions

### Precision Approach

**Implementation:** Rate limits are only normalized to 18 decimals in multi-asset scenarios.

| Scenario | Behavior |
|----------|----------|
| **Single-asset operations** | Rate limits tracked in native token decimals (e.g., 6 decimals for USDC) |
| **Multi-asset operations** | Values normalized to 18 decimals for consistent comparison |

**Rationale:** This approach minimizes unnecessary decimal conversions and potential precision loss in single-asset scenarios while maintaining accuracy when cross-asset comparisons are needed.

### Cancellation Policy

#### Mainnet PSM (With Cancellation)

**Decision:** Rate limits **are** cancelled in the Mainnet PSM integration.

| Operation | Rate Limit Behavior |
|-----------|---------------------|
| `swapUSDSToUSDC` | Decreases rate limit |
| `swapUSDCToUSDS` | **Cancels** (increases) rate limit |

**Rationale:** Swapping USDC back to USDS effectively returns value to the system, so the rate limit is restored.

#### PSM3 Integration (No Cancellation, No minShares)

**Decision:** Rate limits are **not** cancelled in the PSM3 integration (ForeignController).

| Operation | Rate Limit Behavior |
|-----------|---------------------|
| `depositPSM` | Decreases rate limit |
| `withdrawPSM` | Decreases rate limit (no cancellation) |

**Additional Decision:** `minShares` parameter is not added to PSM3 operations.

**Rationale:**
- The PSM3 integration will be deprecated soon, making additional safety mechanisms a poor investment of development resources
- The PSM3 contract is immutable, limiting the attack surface
- Prices cannot be manipulated in PSM3 due to its design (1:1 swap mechanism)
- Risk window is time-limited due to planned deprecation

#### Maple Integration (No Cancellation)

**Decision:** Maple cancel redemption requests and deposits are **not** rate-limit cancelled.

**Rationale:**
- Maple pools are permissioned environments
- Pool dynamics are slower-moving compared to DEX liquidity
- Lower risk of rapid value extraction

---

## Rate Limit Uses

The current uses of rate limits can be seen in [`./printers/rate_limits.py`](../printers/rate_limits.py) (for both the Foreign and Mainnet controllers). The file is also an executable [Wake](https://github.com/Ackee-Blockchain/wake) printer, which can verify that the information in the file is correct at any time.

### Running the Rate Limits Printer

Install Wake using one of:

```bash
uv tool install eth-wake
pipx install eth-wake
pip install eth-wake
```

Execute the printer:

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

A zero exit-code indicates the spec is satisfied.

### Regenerating Wake Config

If `printers/wake.toml` goes out of sync, regenerate it:

```bash
wake up config
```

This reads Foundry remappings and creates a new `wake.toml` file (which can then be moved to `/printers`).

---

## Rate Limit Configuration Guidelines

Rate limits must take into account:

1. **Risk tolerance** for a given protocol
2. **Griefing attacks** (e.g., repetitive transactions with high slippage by malicious relayer)
