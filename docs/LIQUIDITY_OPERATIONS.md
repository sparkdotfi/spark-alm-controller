# Liquidity Operations

This document describes the stablecoin market making, swapping, and liquidity provision functionality in the Spark ALM Controller, including Curve, Uniswap V4, and OTC integrations.

## Overview

The Spark Liquidity Layer (SLL) performs liquidity operations across multiple venues:

| Venue | Operations | Use Case |
|-------|------------|----------|
| **Curve** | Add/remove liquidity, swaps | Deep stablecoin liquidity pools |
| **Uniswap V4** | Swaps | On-chain stablecoin swaps |
| **OTC Desks** | Offchain swaps | High-volume institutional liquidity |

---

## Asset Assumptions

### 1:1 Asset Parity

**Assumption:** All assets used in swaps and liquidity operations are always 1:1 with each other.

**Rationale:** The system is designed to handle USD stablecoins (USDC, USDT, DAI, USDS) which are treated as having equivalent value.

**Implication:** No additional price oracles or slippage calculations are required for these asset pairs within the system.

**Risk:** If assets depeg significantly from each other, the 1:1 assumption breaks down. This is an accepted protocol risk that should be monitored operationally.

---

## Curve Integration

### Supported Operations

- **Add Liquidity:** Deposit stablecoins into Curve pools to receive LP tokens
- **Remove Liquidity:** Burn LP tokens to receive underlying stablecoins
- **Swaps:** Exchange between stablecoins in Curve pools

### Rate Limiting

Curve operations use two rate limit keys per pool:
- **Add liquidity rate limit:** Controls the value deposited into pools
- **Swap rate limit:** Controls the implicit swap value when deposits are imbalanced

### Slippage Protection

All Curve operations require `maxSlippage` to be configured (cannot be zero). The slippage check uses the pool's virtual price to ensure minimum acceptable returns.

---

## Uniswap V4 Integration

### Supported Operations

- **Swaps:** Exchange between stablecoins via Uniswap V4 pools

### Operational Requirements

- All Uniswap V4 pool onboardings must be done with 1:1 assets only
- Pools must have rate limits configured before use
- Rate limit keys whitelist specific pools for interaction

---

## OTC Swaps (Offchain Swap Support)

The OTC swap module allows the SLL to perform offchain swaps with OTC desks and exchanges while ensuring constraints on capital outside the system.

### How It Works

1. Funds are sent from the ALM Proxy to the offchain destination
2. The contract prevents sending more funds until the required balance is returned
3. Acts as a gating mechanism that only allows a maximum `X` of funds to be outside the system per approved OTC exchange at any time

This provides strong guarantees to Spark/Sky that at most `X` can be stolen/lost per whitelisted OTC route, while still allowing rapid throughput into high-liquidity offchain markets.

### System Diagram

![Offchain Swap Module](https://github.com/user-attachments/assets/9aed5b7f-0b6e-45e3-8ad8-10bc5016470d)

### OTC Swap Conditions

For an OTC swap to be performed, `isOtcSwapReady(exchange)` must return `true`. This function has two main components:

#### Slippage

`maxSlippages` mapped on `exchange`, used consistently with other parts of the controller. This value calculates a minimum viable amount to be returned from a swap for it to be considered complete.

#### Recharge Rate

The OTC struct contains a `rechargeRate` value expressed in 18 decimals of token per second. This value increases over time after the initial swap is sent.

**Purpose:** Prevents the configuration from bricking swapping functionality if an exchange returns a material amount of funds that is below the configured `maxSlippage`. The mechanism allows the OTC swap returned amount to virtually "recharge" over time until it eventually exceeds the required amount.

#### Ready Condition

An OTC swap is ready when:

$$claimedAmount + (blockTimestamp - sentTimestamp) \times rechargeRate \ge sentAmount \times maxSlippage$$

### OTC Buffer Configuration

#### Infinite Allowance Requirement

**Requirement:** OTC buffers need to have an infinite allowance to the ALMProxy.

| Aspect | Details |
|--------|---------|
| **Configuration** | OTC buffer contracts must be configured with `type(uint256).max` approval to the `ALMProxy` contract |
| **Security Analysis** | See Octane Security Analysis - Infinite Approval |

**Rationale:**
- Allows the ALMProxy to pull funds from OTC buffer contracts atomically during swap completion
- Eliminates the need for repeated approvals, reducing gas costs and operational complexity
- OTC buffer contracts are specifically designed and whitelisted for this purpose
- The ALMProxy is governance-controlled and highly trusted within the system architecture

**Operational Note:** During OTC buffer deployment, this infinite allowance must be set as part of the initialization process.

### OTC Trust Assumptions

| Assumption | Details |
|------------|---------|
| Fund return method | Funds return to the OTC Buffer contract via transfer (accommodates exchanges that can only send tokens to an address) |
| Maximum loss | Limited to the single outstanding OTC swap amount for a given exchange |
| Recharge rate | Configured low enough that the system will not practically allow multiple swaps in a row without receiving material funds |

---

## Operational Requirements Summary

| Integration | Requirement |
|-------------|-------------|
| **All** | Rate limits must be configured for specific pools/venues |
| **Curve** | Pools must be seeded with initial liquidity before whitelisting (see [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md)) |
| **Uniswap V4** | Only 1:1 asset pools can be onboarded |
| **OTC** | Buffer contracts must have infinite allowance to ALMProxy |
