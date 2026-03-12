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
    "CurveLib/min-amount-not-met"
);
```

See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md#curve-pool-seeding) for seeding requirements.

---

## CCTPLib.transfer - maxFee Validation with Chunked Transfers

**Location:** `src/libraries/CCTPLib.sol` - `transfer` function

**Known Issue:** When a transfer exceeds `burnLimit` and is split into chunks, the same `maxFee` is passed to each `depositForBurn` call. The last chunk may be smaller than `maxFee`, causing the `maxFee < amount` check to revert at the CCTP level.

**Practical Impact:** Negligible. In practice, CCTP relay fees are orders of magnitude smaller than `burnLimit`, so the last chunk will almost always exceed `maxFee`.

---

## CCTPLib.transfer - Zero Burn Limit

**Location:** `src/libraries/CCTPLib.sol` - `transfer` function

**Known Issue:** If Circle sets `burnLimitsPerMessage` to zero, the loop passes `amount = 0` to `depositForBurn()`, reverting with a misleading `"Amount must be nonzero"` error instead of indicating a zero burn limit.

---

## CCTPLib.transfer - Gas Exhaustion from Small Burn Limits

**Location:** `src/libraries/CCTPLib.sol` - `transfer` function

**Known Issue:** If Circle drastically reduces `burnLimitsPerMessage`, large transfers could require thousands of loop iterations, exceeding the block gas limit. No funds are at risk as the transaction simply reverts.

---

## Error Message Prefixes

Error messages follow the pattern `ContractOrLibName/error-description`. Each library uses its own prefix:

### Controller and Core Contract Prefixes

| Prefix | Source |
|--------|--------|
| `MC/` | MainnetController |
| `FC/` | ForeignController |
| `RateLimits/` | RateLimits contract |
| `OTCBuffer/` | OTCBuffer contract |
| `WEETHModule/` | WEETHModule contract |

### Library Prefixes

| Prefix | Source |
|--------|--------|
| `AaveLib/` | Aave deposit/withdraw operations |
| `ApproveLib/` | Token approval utility |
| `CCTPLib/` | CCTP V2 bridging operations |
| `CentrifugeLib/` | Centrifuge vault operations |
| `CurveLib/` | Curve pool operations |
| `ERC4626Lib/` | ERC-4626 vault operations |
| `ERC7540Lib/` | ERC-7540 async vault operations |
| `LayerZeroLib/` | LayerZero V2 bridging operations |
| `MapleLib/` | Maple redemption operations |
| `MerklLib/` | Merkl operator operations |
| `OTCLib/` | OTC swap operations |
| `PendleLib/` | Pendle PT redemption operations |
| `TransferAssetLib/` | Generic asset transfer operations |
| `UniswapV4Lib/` | Uniswap V4 operations |
| `WEETHLib/` | weETH deposit/withdraw operations |

Libraries without custom error messages (use only rate limit reverts): `DAIUSDSLib`, `FarmLib`, `PSMLib`, `PSM3Lib`, `SparkVaultLib`, `SuperstateLib`, `USDELib`, `USDSLib`, `WrapProxyETHLib`, `WSTETHLib`.

---

## Slippage Checks

All swap and liquidity operations require `maxSlippage != 0`. Each library enforces this with its own prefix:

```solidity
require(params.maxSlippage != 0, "CurveLib/max-slippage-not-set");
require(params.maxSlippage != 0, "AaveLib/max-slippage-not-set");
require(params.maxSlippage != 0, "UniswapV4Lib/max-slippage-not-set");
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
| `makeAddressKey` | `(bytes32 limit, address)` | Most libraries (ERC4626, Aave, Curve, etc.) |
| `makeBytes32Key` | `(bytes32 limit, bytes32)` | UniswapV4Lib (pool ID) |
| `makeUint32Key` | `(bytes32 limit, uint32)` | CCTPLib (destination domain) |
| `makeAddressUint32Key` | `(bytes32 limit, address, uint32)` | LayerZeroLib (OFT + endpoint) |
| `makeAddressUint16Key` | `(bytes32 limit, address, uint16)` | CentrifugeLib (vault + region ID) |
| `makeAddressAddressKey` | `(bytes32 limit, address, address)` | TransferAssetLib (asset + destination) |

See [Rate Limits](./RATE_LIMITS.md#whitelisting-via-rate-limit-keys) for design rationale.
