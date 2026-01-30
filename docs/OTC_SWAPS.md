# OTC Swaps (Offchain Swap Support)

This document describes the offchain swap functionality that allows the Spark Liquidity Layer (SLL) to perform swaps with OTC desks and exchanges.

## Overview

The OTC swap module allows the SLL to perform offchain swaps while ensuring constraints on how much capital has left the system at any time. It provides access to liquidity from sources such as OTC desks and exchanges.

### How It Works

1. Funds are sent from the ALM Proxy to the offchain destination
2. The contract prevents sending more funds until the required balance is returned
3. Acts as a gating mechanism that only allows a maximum `X` of funds to be outside the system per approved OTC exchange at any time

This provides strong guarantees to Spark/Sky that at most `X` can be stolen/lost per whitelisted OTC route, while still allowing rapid throughput into high-liquidity offchain markets.

### System Diagram

![Offchain Swap Module](https://github.com/user-attachments/assets/9aed5b7f-0b6e-45e3-8ad8-10bc5016470d)

---

## OTC Swap Conditions

For an OTC swap to be performed, `isOtcSwapReady(exchange)` must return `true`. This function has two main components:

### Slippage

`maxSlippages` mapped on `exchange`, used consistently with other parts of the controller. This value calculates a minimum viable amount to be returned from a swap for it to be considered complete.

### Recharge Rate

The OTC struct contains a `rechargeRate` value expressed in 18 decimals of token per second. This value increases over time after the initial swap is sent.

**Purpose:** Prevents the configuration from bricking swapping functionality if an exchange returns a material amount of funds that is below the configured `maxSlippage`. The mechanism allows the OTC swap returned amount to virtually "recharge" over time until it eventually exceeds the required amount.

### Ready Condition

An OTC swap is ready when:

$$claimedAmount + (blockTimestamp - sentTimestamp) \times rechargeRate \ge sentAmount \times maxSlippage$$

---

## OTC Swap Configuration

### Infinite Allowance Requirement

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

---

## Trust Assumptions

The following assumptions apply to the OTC swap module:

| Assumption | Details |
|------------|---------|
| Fund return method | Funds return to the OTC Buffer contract via transfer (accommodates exchanges that can only send tokens to an address) |
| Maximum loss | Limited to the single outstanding OTC swap amount for a given exchange |
| Recharge rate | Configured low enough that the system will not practically allow multiple swaps in a row without receiving material funds |

---

## Asset Assumptions

### 1:1 Asset Parity in OTC Swaps and UniswapV4

**Assumption:** All assets used in OTC swaps and UniswapV4 integrations are always 1:1 with each other.

**Rationale:** The system is designed to handle USD stablecoins (USDC, USDT, DAI, USDS) which are treated as having equivalent value.

**Implication:** No additional price oracles or slippage calculations are required for these asset pairs within the system.

**Risk:** If assets depeg significantly from each other, the 1:1 assumption breaks down. This is an accepted protocol risk that should be monitored operationally.

---

## Operational Requirements

- All Uniswap V4 pool onboardings are to be done with 1:1 assets
- Rate limits must be configured appropriately for OTC operations
- OTC buffer contracts must have infinite allowance set during deployment
