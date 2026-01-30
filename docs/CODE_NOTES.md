# Code Implementation Notes

This document captures specific implementation decisions and behaviors that may not be immediately obvious from reading the code.

---

## CurveLib.addLiquidity - Virtual Price Zero Handling

**Location:** `src/libraries/CurveLib.sol` - `addLiquidity` function

**Behavior:** Reverts when `get_virtual_price() == 0`.

**Intention:** Prevents adding liquidity to unseeded pools, which could lead to unfavorable exchange rates.

```solidity
// Intentionally reverts when get_virtual_price() == 0 to prevent adding liquidity to unseeded pools
require(
    params.minLpAmount >= valueDeposited
        * params.maxSlippage
        / curvePool.get_virtual_price(),
    "MC/min-amount-not-met"
);
```

See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md#curve-pool-seeding) for seeding requirements.

---

## Error Message Prefixes

| Prefix | Source |
|--------|--------|
| `MC/` | MainnetController or shared controller logic |
| `FC/` | ForeignController-specific logic |
| `RL/` | RateLimits contract |

---

## Slippage Checks

All swap and liquidity operations require `maxSlippage != 0`:

```solidity
require(params.maxSlippage != 0, "MC/max-slippage-not-set");
```

**Rationale:** Zero slippage would disable protection, allowing arbitrarily bad trades by compromised relayers.

---

## Rate Limit Key Generation

Rate limit keys combine a function identifier with an address via `keccak256`. This provides:
- Granular per-integration rate limiting
- Implicit whitelisting (only configured addresses work)
- Flexibility for future function signatures

See `RateLimitHelpers.sol` for utilities and [Rate Limits](./RATE_LIMITS.md#whitelisting-via-rate-limit-keys) for design rationale.
