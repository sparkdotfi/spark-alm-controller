# Aave V4 Integration

This document describes the Aave V4 integration with the PAU system. It covers the `AaveV4Facet`, the hub-and-spoke model it integrates with, how a non-tokenized supply position is measured and rate-limited, and the per-market slippage control that governs deposits.

Protocol behavior described here was checked against the Aave V4 codebase at commit `cfdf931c8c61715bef590c087c1fabe64c92ac92` (v0.5.11 line, 2026-07).

## Overview

Aave V4 replaces the V3 pool model with a **hub-and-spoke** architecture:

- A **Hub** holds the pooled liquidity for each asset and does the share accounting (`add` / `remove`), keyed by `assetId`.
- A **Spoke** is the user-facing market. It maps a `reserveId` to `(underlying, hub, assetId)`, tracks each user's position, and enforces reserve-level controls (pause, freeze).

A market is therefore identified by the pair **`(spoke, reserveId)`**. There is **no aToken or receipt token**: the supplied position is a share balance recorded in spoke storage, read via `spoke.getUserSuppliedAssets(reserveId, user)`.

The `AaveV4Facet` is a **supply-only** integration: it supplies underlying from the ALMProxy into a market and withdraws it back. It does not borrow, does not enable collateral usage (Aave V4 supply does not auto-enable collateral), and holds no intermediate token. The ALMProxy interacts with the spoke for its own position (`onBehalfOf = ALMProxy`), which Aave V4 always authorizes (`user == manager`), so no position-manager onboarding is required.

## Token Flow

```
Deposit:  underlying (ALMProxy) → approve spoke → spoke.supply → hub.add (liquidity)
          position += suppliedShares (spoke storage, no receipt token)

Withdraw: spoke.withdraw → hub.remove → underlying (ALMProxy)
          position -= withdrawnShares
```

---

## Operations

### Deposit (supply underlying)

**Function:** `deposit(spoke, reserveId, amount)` (`ALLOCATOR_ROLE`)

**Flow:**

1. Read `maxSlippage` for `(spoke, reserveId)`; revert `AaveV4Facet/max-slippage-not-set` if it is zero. A market must be explicitly configured before it can receive deposits.
2. Read the reserve from `spoke.getReserve(reserveId)`, resolving `underlying`, `hub`, and `assetId`.
3. Require `hub.getAssetDeficitRay(assetId) == 0`; revert `AaveV4Facet/asset-deficit` otherwise. Aave V4 deficits (socialized bad debt) never mark down the supplier share price, so supplying into a deficit-carrying asset buys into the pool at par against unbacked debt. Deposits are blocked until the deficit is cleared.
4. Decrement `LIMIT_AAVE_V4_DEPOSIT` keyed `(spoke, reserveId, hub, assetId, underlying)` by `amount`.
5. Approve `underlying` from the ALMProxy to the spoke, snapshot the supplied position, then `doCall` `spoke.supply(reserveId, amount, proxy)`.
6. Measure `amountReceived` as the supplied-position delta (`getUserSuppliedAssets` after minus before) rather than trusting the `(shares, amount)` tuple the spoke returns, and require `amountReceived >= amount * maxSlippage / 1e18`; revert `AaveV4Facet/slippage-too-high` otherwise.
7. Reset the approval to zero in case the spoke did not pull the full amount.

**Rate Limit:** `LIMIT_AAVE_V4_DEPOSIT` via `makeAddressUint256AddressUint16AddressKey(LIMIT_AAVE_V4_DEPOSIT, spoke, reserveId, hub, assetId, underlying)`.

The reserve-derived values are embedded in the key deliberately: `getReserve(reserveId)` is a mutable third-party read, and a spoke that remaps a reserve must not be able to spend a budget governance configured for the original mapping. Each component covers a distinct trust surface: `underlying` because the facet approves and transfers it, `hub` because it is the deficit gate's target, `assetId` because it is the parameter passed into that gate. Remapping any of them invalidates the key, so deposits stop until governance configures a new limit for the new tuple.

**Event:** `AaveV4Deposit(spoke, reserveId, amount)`. `amount` is the requested supply amount; the measured position delta is enforced against the slippage floor rather than emitted.

**Zero amount:** reverts inside Aave V4 (`Hub.add` requires `amount > 0`, error `InvalidAmount()`); the facet adds no zero-check of its own.

### Withdraw (reclaim underlying)

**Function:** `withdraw(spoke, reserveId, amount) returns (amountWithdrawn)` (`ALLOCATOR_ROLE`)

**Flow:**

1. Read the full `Reserve` struct from `spoke.getReserve(reserveId)`: `underlying` for the balance measurement, `hub` and `assetId` for the deposit-key refill in step 4.
2. Snapshot the ALMProxy `underlying` balance, then `doCall` `spoke.withdraw(reserveId, amount, proxy)`. The spoke caps the request at the full position size (`min(amount, previewRemoveByShares(...))`), so passing `type(uint256).max` withdraws the entire supplied position.
3. Measure `amountWithdrawn` as the ALMProxy balance delta rather than trusting the spoke's return value.
4. Decrement `LIMIT_AAVE_V4_WITHDRAW` keyed `(spoke, reserveId)` by `amountWithdrawn`, and `_tryIncreaseRateLimit` the deposit key by the same amount (see [Try-Increase](./RATE_LIMITS.md#try-increase-not-gate-check): the refill silently no-ops if the deposit key is unconfigured, and the deposit key is not a precondition for withdrawal). This is the fail-safe direction for reserve remaps: a reserve remapped between deposit and withdraw still exits fine, but the refill resolves to the unconfigured new-tuple key and no-ops.

**Rate Limit:** `LIMIT_AAVE_V4_WITHDRAW` via `makeAddressUint256Key(LIMIT_AAVE_V4_WITHDRAW, spoke, reserveId)`. The withdraw key embeds none of the reserve-derived values: withdrawals return funds to custody, so a reserve remap is not a budget-theft vector on this path, and the measured balance delta already sizes the decrement in whatever token arrived.

**Event:** `AaveV4Withdraw(spoke, reserveId, amountWithdrawn)`, emitting the measured balance delta, not the caller-supplied `amount`.

**No slippage parameter:** withdrawal has no exchange-rate leg. The hub transfers exactly the requested amount or reverts (`InsufficientLiquidity`); it never partially fills.

**Zero amount:** reverts inside Aave V4 (`Hub.remove` requires `amount > 0`, error `InvalidAmount()`). A `type(uint256).max` withdrawal on an empty position resolves to zero and reverts the same way.

### Set Max Slippage (admin)

**Function:** `setMaxSlippage(spoke, reserveId, maxSlippage)` (`DEFAULT_ADMIN_ROLE`)

Sets the per-market deposit tolerance, 1e18-scaled (higher = stricter):

- `spoke` must be nonzero: `AaveV4Facet/spoke-zero-address`.
- `maxSlippage` itself is unbounded; value bounds belong at the spell/config layer, consistent with the other facets. A value of `1e18` or above is accepted but wedges deposits: an at-least-1:1 requirement is only satisfiable while the share price is exactly 1:1, and once the reserve accrues interest, floor rounding in the shares round-trip leaves the credited position below `amount`, so every deposit reverts. The fork test `test_depositAaveV4_usdc_slippageOneToOneAfterAccrualBoundary` pins both sides of the boundary: `1e18` reverts after accrual while `1e18 - 1` still admits a deposit, so accrual can never wedge a market configured below `1e18`.
- Setting `maxSlippage` back to `0` disables deposits for the market (`deposit` requires it nonzero); withdrawals are unaffected.

**Event:** `AaveV4MaxSlippageSet(spoke, reserveId, maxSlippage)`

Together with the deposit rate-limit key, the nonzero `maxSlippage` acts as the per-market whitelist: both must be configured by governance before the first deposit.

### Views

| Function | Returns |
| --- | --- |
| `getDepositRateLimitKey(spoke, reserveId, hub, assetId, underlying)` | `makeAddressUint256AddressUint16AddressKey(LIMIT_AAVE_V4_DEPOSIT, spoke, reserveId, hub, assetId, underlying)` |
| `getWithdrawRateLimitKey(spoke, reserveId)` | `makeAddressUint256Key(LIMIT_AAVE_V4_WITHDRAW, spoke, reserveId)` |
| `getMaxSlippage(spoke, reserveId)` | Configured tolerance, `0` when unset |

---

## Rate Limit Keys

| Limit | Key tuple | Helper |
| --- | --- | --- |
| `LIMIT_AAVE_V4_DEPOSIT` | `(spoke, reserveId, hub, assetId, underlying)` | `makeAddressUint256AddressUint16AddressKey` |
| `LIMIT_AAVE_V4_WITHDRAW` | `(spoke, reserveId)` | `makeAddressUint256Key` |

`withdraw` refills the deposit key by the withdrawn amount (`_tryIncreaseRateLimit`), so capital rotated out of a market restores deposit headroom for that market without governance action.

---

## Security Considerations

### Aave Governance and Upgradability

Every Aave V4 contract the facet touches (spoke and hub) is an upgradeable proxy controlled by Aave governance through a single AccessManager. A hostile or compromised upgrade can take the full supplied position; the facet cannot defend against its counterparty. Exposure is bounded by position sizing and the per-market deposit rate limit, not by facet code.

### Deficit Is Exit-Liquidity Risk, Not a Markdown

When bad debt is socialized in Aave V4, the hub records a deficit (`getAssetDeficitRay`) but the supplier share price is never marked down. The loss surfaces as exit liquidity: the last suppliers out cannot fully withdraw. The facet's deficit gate stops new capital from buying into unbacked debt at par, but it does not protect the existing position; monitoring hub liquidity against position size is an operational requirement.

### Withdrawal Availability

A withdrawal either transfers the requested amount in full or reverts; there are no partial fills. It reverts when:

- the hub lacks liquidity (`InsufficientLiquidity`),
- the reserve is paused on the spoke (`ReservePaused`); a **frozen** reserve still allows withdrawal (freeze blocks supply/borrow only),
- the hub has the spoke deactivated or halted (`SpokeNotActive`, `SpokeHalted`).

The hub's reinvestment controller may deploy idle liquidity elsewhere, which reduces immediately withdrawable liquidity without touching the position.

### Measured Deltas, Not Return Values

Both operations size their accounting from observed state changes (supplied-position delta on deposit, balance delta on withdraw) rather than the spoke's return values, so a spoke that misreports cannot skew rate-limit accounting, and deposit shortfalls from rounding or donation-style manipulation are caught by the slippage floor.

### No Standing Approvals

The deposit approval is reset to zero after the supply call. Outside a `deposit` transaction, the spoke holds no allowance on ALMProxy funds.

### Reentrancy

All interactive functions are `nonReentrant`.

---

## Failure Modes

| Revert | Origin | Cause |
| --- | --- | --- |
| `AaveV4Facet/max-slippage-not-set` | facet | `deposit` on a market with no configured `maxSlippage` |
| `AaveV4Facet/asset-deficit` | facet | `deposit` while the hub asset carries a deficit |
| `AaveV4Facet/slippage-too-high` | facet | credited position below `amount * maxSlippage / 1e18` |
| `AaveV4Facet/spoke-zero-address` | facet | `setMaxSlippage` with zero spoke |
| `RateLimits/rate-limit-exceeded` | rate limits | deposit or withdraw exceeding the configured limit, or key unconfigured |
| `InvalidAmount()` | Aave V4 hub | zero-amount supply or withdraw |
| `InsufficientLiquidity(...)` | Aave V4 hub | withdrawal exceeding available hub liquidity |
| `ReservePaused()` / `ReserveFrozen()` | Aave V4 spoke | reserve paused (blocks both); frozen blocks supply only |
| `SpokeNotActive()` / `SpokeHalted()` | Aave V4 hub | hub-side spoke deactivation or halt |

---

## Operational Requirements

### Configuration (per market, before first deposit)

1. `setMaxSlippage(spoke, reserveId, maxSlippage)`: required, nonzero. `0.9999e18` is the standard tolerance; values at or above `1e18` wedge deposits once the reserve accrues interest, and tighter values risk spurious reverts on low-decimal assets once the share price exceeds 1:1.
2. Configure `LIMIT_AAVE_V4_DEPOSIT` keyed `(spoke, reserveId, hub, assetId, underlying)`.
3. Configure `LIMIT_AAVE_V4_WITHDRAW` keyed `(spoke, reserveId)`. The withdraw path is gated only by this key; the deposit key is refilled opportunistically and zeroing it does not pause withdrawals.

No seeding is required: the integration holds no intermediate token and uses no auxiliary module.

### Monitoring

- **Proxy upgrades**: `Upgraded` events on the spoke and hub proxies, plus admin changes on their proxy admins and on the Aave AccessManager. A hostile or buggy upgrade is the single largest risk to the position (see [Aave Governance and Upgradability](#aave-governance-and-upgradability)); alert immediately on any upgrade and treat an unannounced one as an exit trigger.
- **Hub deficit** (`getAssetDeficitRay` per asset): nonzero blocks deposits and signals socialized bad debt accruing exit-liquidity risk.
- **Hub liquidity vs. position size**: the withdrawable amount is capped by hub liquidity, which the reinvestment controller can reduce.
- **Spoke/hub control states**: reserve pause, hub-side spoke deactivation or halt, all of which block withdrawal.
- **Reserve remaps**: a change in any of `getReserve(reserveId)`'s `.underlying`, `.hub`, or `.assetId` invalidates the deposit key and warrants investigation.

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md): overall facet architecture and Controller dispatch.
- [RATE_LIMITS.md](./RATE_LIMITS.md): rate-limit key construction, try-increase and gate-check patterns.
