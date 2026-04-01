# Code Implementation Notes

This document captures specific implementation decisions and behaviors that may not be immediately obvious from reading the code.

---

## CurveFacet.addLiquidity - Virtual Price Zero Handling

**Location:** `src/facets/curve/CurveFacet.sol` - `addLiquidity` function

**Behavior:** Reverts when `get_virtual_price() == 0`.

**Intention:** Prevents adding liquidity to unseeded pools, which could lead to unfavorable exchange rates.

```solidity
// Intentionally reverts when get_virtual_price() == 0 to prevent adding liquidity to unseeded pools
require(
    params.minLpAmount >= valueDeposited
        * params.maxSlippage
        / curvePool.get_virtual_price(),
    "CurveFacet/min-amount-not-met"
);
```

See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md#curve-pool-seeding) for seeding requirements.

---

## CCTPFacet.transfer - maxFee Validation with Chunked Transfers

**Location:** `src/facets/cctp/CCTPFacet.sol` - `transfer` function

**Known Issue:** When a transfer exceeds `burnLimit` and is split into chunks, the same `maxFee` is passed to each `depositForBurn` call. The last chunk may be smaller than `maxFee`, causing the `maxFee < amount` check to revert at the CCTP level.

**Practical Impact:** Negligible. In practice, CCTP relay fees are orders of magnitude smaller than `burnLimit`, so the last chunk will almost always exceed `maxFee`.

---

## CCTPFacet.transfer - Zero Burn Limit

**Location:** `src/facets/cctp/CCTPFacet.sol` - `transfer` function

**Known Issue:** If Circle sets `burnLimitsPerMessage` to zero, the loop passes `amount = 0` to `depositForBurn()`, reverting with a misleading `"Amount must be nonzero"` error instead of indicating a zero burn limit.

---

## CCTPFacet.transfer - Gas Exhaustion from Small Burn Limits

**Location:** `src/facets/cctp/CCTPFacet.sol` - `transfer` function

**Known Issue:** If Circle drastically reduces `burnLimitsPerMessage`, large transfers could require thousands of loop iterations, exceeding the block gas limit. No funds are at risk as the transaction simply reverts.

---

## Error Message Prefixes

Error messages follow the pattern `ComponentName/error-description`. Each facet and supporting contract uses its own prefix:

### Controller and Core Contract Prefixes

| Prefix | Source |
|--------|--------|
| `Controller/` | Controller contract |
| `RateLimits/` | RateLimits contract |
| `OTCBuffer/` | OTCBuffer contract |
| `WEETHModule/` | WEETHModule contract |

### Facet Prefixes

| Prefix | Source |
|--------|--------|
| `AaveFacet/` | Aave deposit/withdraw operations |
| `CCTPFacet/` | CCTP V2 bridging operations |
| `CentrifugeFacet/` | Centrifuge vault operations |
| `CurveFacet/` | Curve pool operations |
| `ERC4626Facet/` | ERC-4626 vault operations |
| `LayerZeroFacet/` | LayerZero V2 bridging operations |
| `MapleFacet/` | Maple redemption operations |
| `OTCFacet/` | OTC swap operations |
| `PendleFacet/` | Pendle PT redemption operations |
| `TransferAssetFacet/` | Generic asset transfer operations |
| `UniswapV3Facet/` | Uniswap V3 operations |
| `UniswapV4Facet/` | Uniswap V4 operations |
| `WEETHFacet/` | weETH deposit/withdraw operations |

### Library Prefixes

| Prefix | Source |
|--------|--------|
| `ApproveLib/` | Token approval utility |

Facets without custom error messages (use only rate limit reverts): `DAIUSDSFacet`, `ERC7540Facet`, `FarmFacet`, `MerklFacet`, `PSMFacet`, `PSM3Facet`, `SparkVaultFacet`, `SuperstateFacet`, `USDEFacet`, `USDSFacet`, `WrapProxyETHFacet`, `WSTETHFacet`.

---

## Slippage Checks

All swap and liquidity operations require `maxSlippage != 0`. Each facet enforces this with its own prefix:

```solidity
require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");
require(maxSlippage != 0, "AaveFacet/max-slippage-not-set");
require(maxSlippage != 0, "UniswapV4Facet/max-slippage-not-set");
```

**Rationale:** Zero slippage would disable protection, allowing arbitrarily bad trades by compromised relayers.

---

## Rate Limit Key Generation

Rate limit keys combine a function identifier with contextual data via `keccak256`. This provides:
- Granular per-integration rate limiting
- Implicit whitelisting (only configured addresses work)
- Flexibility for future function signatures

### Key Construction Helpers

`RateLimitHelpers.sol` provides multiple helpers for different key patterns:

| Helper | Parameters | Used By |
|--------|------------|---------|
| `makeAddressKey` | `(bytes32 limit, address)` | Most facets (ERC4626, Aave, Curve, etc.) |
| `makeBytes32Key` | `(bytes32 limit, bytes32)` | UniswapV4Facet (pool ID) |
| `makeUint32Key` | `(bytes32 limit, uint32)` | CCTPFacet (destination domain) |
| `makeAddressUint32Key` | `(bytes32 limit, address, uint32)` | LayerZeroFacet (OFT + endpoint) |
| `makeAddressUint16Key` | `(bytes32 limit, address, uint16)` | CentrifugeFacet (vault + region ID) |
| `makeAddressAddressKey` | `(bytes32 limit, address, address)` | TransferAssetFacet (asset + destination) |

See [Rate Limits](./RATE_LIMITS.md#whitelisting-via-rate-limit-keys) for design rationale.
