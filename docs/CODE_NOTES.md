# Code Implementation Notes

This document captures specific implementation decisions and behaviors that may not be immediately obvious from reading the code.

---

## CurveLib.addLiquidity - Virtual Price Zero Handling

**Location:** `src/libraries/CurveLib.sol` - `addLiquidity` function

**Behavior:** The function will revert when `get_virtual_price() == 0`.

**Intention:** This is intentional behavior designed to prevent adding liquidity to unseeded pools.

### Rationale

- Unseeded Curve pools (pools with no liquidity) have a virtual price of zero
- Adding liquidity to an unseeded pool can lead to unfavorable exchange rates and potential value loss
- By reverting on zero virtual price (via division by zero), the contract enforces that pools must be properly initialized before the ALM system interacts with them

### Relevant Code

```solidity
// In CurveLib.addLiquidity()
// Intentionally reverts when get_virtual_price() == 0 to prevent adding liquidity to unseeded pools
require(
    params.minLpAmount >= valueDeposited
        * params.maxSlippage
        / curvePool.get_virtual_price(),
    "MC/min-amount-not-met"
);
```

### Operational Requirement

Ensure Curve pools are seeded with initial liquidity before whitelisting them for ALM Controller operations. See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md#curve-pool-seeding) for details.

---

## Error Message Prefixes

The codebase uses standardized error message prefixes to indicate the source contract:

| Prefix | Source |
|--------|--------|
| `MC/` | MainnetController or shared controller logic |
| `FC/` | ForeignController-specific logic |
| `RL/` | RateLimits contract |

---

## Rate Limit Key Generation

Rate limit keys are generated using `keccak256` hashes, typically combining:
- A function identifier
- An address (e.g., pool address, token address)

This approach allows:
- Flexibility in future function signatures
- Granular rate limiting per protocol/asset combination
- Consistent identification across controller versions
- **Implicit whitelisting** of specific integrations (only configured addresses work)

See `RateLimitHelpers.sol` for the key generation utilities.

---

## Slippage Checks

All swap and liquidity operations require `maxSlippage != 0`. This is enforced with explicit checks:

```solidity
require(params.maxSlippage != 0, "MC/max-slippage-not-set");
```

**Rationale:** A zero slippage parameter would effectively disable slippage protection, allowing a compromised relayer to execute trades at arbitrarily bad rates.

---

## wrapAllProxyETH

**Location:** `src/MainnetController.sol`

**Purpose:** Converts all ETH held by the ALMProxy to WETH.

**Access:** `RELAYER` role (not admin-only)

**Use Case:** ETH received from protocol operations (e.g., unwrapping WETH, receiving ETH from contracts) can be converted to WETH for standard token handling.

**Security:** Keeps funds within the ALMProxy - only changes ETH to WETH, doesn't move funds out of the system.
