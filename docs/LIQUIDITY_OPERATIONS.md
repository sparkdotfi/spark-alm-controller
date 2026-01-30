# Liquidity Operations

This document describes the stablecoin market making, swapping, and liquidity provision functionality in the Spark ALM Controller.

## Overview

The Spark Liquidity Layer (SLL) performs liquidity operations across multiple venues:

| Venue | Operations | Use Case |
|-------|------------|----------|
| **Curve** | Add/remove liquidity, swaps | Deep stablecoin liquidity pools |
| **Uniswap V4** | Swaps, positions | On-chain stablecoin swaps |
| **OTC Desks** | Offchain swaps | High-volume institutional liquidity |

**Asset Assumption:** All assets in these operations are treated as 1:1 (USD stablecoins). See [Threat Model](./THREAT_MODEL.md#core-assumption-11-asset-parity) for details.

---

## Curve Integration

### Supported Operations

- **Add Liquidity:** Deposit stablecoins into Curve pools to receive LP tokens
- **Remove Liquidity:** Burn LP tokens to receive underlying stablecoins
- **Swaps:** Exchange between stablecoins in Curve pools

### Rate Limiting

Curve operations use three rate limit keys per pool:
- **Add liquidity rate limit:** Controls the value deposited into pools
- **Swap rate limit:** Controls the implicit swap value when deposits are imbalanced
- **Remove liquidity rate limit:** Controls the value withdrawn from pools

### Slippage Protection

All Curve operations require `maxSlippage` to be configured (cannot be zero). The slippage check uses the pool's virtual price to ensure minimum acceptable returns.

### Seeding Requirement

Curve pools must be seeded with initial liquidity before use. The `addLiquidity` function intentionally reverts when `get_virtual_price() == 0` to prevent interaction with unseeded pools.

---

## Uniswap V4 Integration

### Supported Operations

- **Swaps:** Exchange between stablecoins via Uniswap V4 pools
- **Mint Positions:** Create liquidity positions (if applicable)
- **Increase Positions:** Deposit adfditional liquidity into an existing position
- **Decrease Positions:** Withdraw some or al the liquidity of an existing position

### Requirements

- Only 1:1 stablecoin pools can be onboarded
- Pools must have rate limits configured before use
- Rate limit keys whitelist specific pools for interaction

---

## OTC Swaps (Offchain Swap Support)

The OTC swap module allows offchain swaps with OTC desks and exchanges while constraining capital outside the system.

### How It Works

1. Funds are sent from the ALM Proxy to the offchain destination
2. The contract prevents sending more funds until the required balance is returned
3. Acts as a gating mechanism: maximum `X` funds outside the system per approved exchange

This provides guarantees that at most `X` can be at risk per whitelisted OTC route, while allowing rapid throughput into high-liquidity offchain markets.

### System Diagram

![Offchain Swap Module](https://github.com/user-attachments/assets/9aed5b7f-0b6e-45e3-8ad8-10bc5016470d)

### OTC Swap Conditions

For an OTC swap to be performed, `isOtcSwapReady(exchange)` must return `true`. This function has two main components:

#### Slippage

`maxSlippages` mapped on `exchange`, used consistently with other parts of the controller. This value calculates a minimum viable amount to be returned from a swap for it to be considered complete.

#### Recharge Rate

The OTC struct contains a `rechargeRate` value expressed in 18 decimals of token per second. This value increases over time after the initial swap is sent.

**Purpose:** Prevents the configuration from bricking swapping functionality if an exchange returns an amount of funds that is materially below the configured `maxSlippage`. The mechanism allows the amount that can be sent as part of an OTC swap to virtually "recharge" over time, to respond to deviations in recent expected claims.

#### Ready Condition

An OTC swap is ready when:

$$claimedAmount + (blockTimestamp - sentTimestamp) \times rechargeRate \ge sentAmount \times maxSlippage$$

### OTC Buffer Configuration

OTC buffers require infinite allowance (`type(uint256).max`) to the ALMProxy. This allows atomic fund pulling during swap completion. `otcClaim` always attempts to transfer the entire buffer balance for a whitelisted asset; with finite allowances, an attacker can donate a small amount to push balance above allowance, causing claim reverts and blocking OTC readiness when recharge is zero/low. See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md#otc-buffer-deployment) for deployment checklist.

---

## PSM Integration

There are two PSM integrations with different rate limit behaviors:

### Mainnet PSM (MainnetController)

**Operations:** USDS ↔ USDC swaps (via DAI conversion)

| Operation | Rate Limit |
|-----------|------------|
| `swapUSDSToUSDC` | Decreases limit |
| `swapUSDCToUSDS` | **Cancels** (restores) limit |

**Rationale:** Swapping USDC back to USDS returns value to the system, so rate limit is restored.

### PSM3 (ForeignController)

**Operations:** Deposit/withdraw assets to/from L2 PSM

| Operation | Rate Limit |
|-----------|------------|
| `depositPSM` | Decreases limit |
| `withdrawPSM` | Decreases limit (no cancellation) |

**Design Decision:** No cancellation, no `minShares`.

**Rationale:**
- PSM3 will be deprecated soon
- The contract is immutable, limiting attack surface
- Prices cannot be manipulated due to 1:1 swap design

---

## Operational Requirements

For deployment checklists and configuration requirements, see [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md).
