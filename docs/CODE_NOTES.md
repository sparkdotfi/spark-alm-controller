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

## CCTPFacet.transferWithFee - CCTPv2 Fee Handling

**Location:** `src/facets/cctp/CCTPFacet.sol` - `transferWithFee` function

The current CCTPFacet targets CCTPv2, which will enable a non-zero `maxFee` in the future. To handle this, `transferWithFee` allows the allocator to fetch the CCTPv2 fee off-chain and submit it as a parameter. The original `transfer` function (which hardcodes `maxFee = 0`) is kept for backward compatibility. These two functions may be unified into one after CCTPv2 fees are fully enabled.

---

## Error Message Prefixes

Error messages follow the pattern `ComponentName/error-description`. Each facet and supporting contract uses its own prefix:

### Controller and Core Contract Prefixes

| Prefix         | Source               |
| -------------- | -------------------- |
| `Controller/`  | Controller contract  |
| `RateLimits/`  | RateLimits contract  |
| `OTCBuffer/`   | OTCBuffer contract   |
| `WEETHModule/` | WEETHModule contract |

Additionally, some core contracts use Solidity custom errors (not string-prefix `require` messages):

| Custom Error                       | Source                                |
| ---------------------------------- | ------------------------------------- |
| `CallSelectorAlreadyWired(bytes4)` | IEnumerableIntegrations               |
| `CallSelectorHardcoded(bytes4)`    | IBeacon                               |
| `CallSelectorNotWired(bytes4)`     | IController                           |
| `EmptyArray()`                     | IBeacon, IController                  |
| `EmptyFacet()`                     | IEnumerableIntegrations               |
| `IntegrationNotFound(bytes32)`     | IEnumerableIntegrations               |
| `InvalidCallDataLength(uint256)`   | IController                           |
| `NotAdmin(address)`                | IController                           |
| `ZeroAccessControls()`             | IController                           |
| `ZeroAdmin()`                      | IAccessControls, IBeacon, IRateLimits |
| `ZeroBeacon()`                     | IController, IPAUFactory              |
| `ZeroFacet()`                      | IBeacon                               |
| `ZeroProxy()`                      | IController                           |
| `ZeroRateLimits()`                 | IController                           |

### Facet Prefixes

| Prefix                | Source                            |
| --------------------- | --------------------------------- |
| `AaveFacet/`          | Aave deposit/withdraw operations  |
| `CCTPFacet/`          | CCTP V2 bridging operations       |
| `CentrifugeFacet/`    | Centrifuge vault operations       |
| `CurveFacet/`         | Curve pool operations             |
| `ERC4626Facet/`       | ERC-4626 vault operations         |
| `LayerZeroFacet/`     | LayerZero V2 bridging operations  |
| `MapleFacet/`         | Maple redemption operations       |
| `OTCFacet/`           | OTC swap operations               |
| `PendleFacet/`        | Pendle PT redemption operations   |
| `TransferAssetFacet/` | Generic asset transfer operations |
| `UniswapV3Facet/`     | Uniswap V3 operations             |
| `UniswapV4Facet/`     | Uniswap V4 operations             |
| `WEETHFacet/`         | weETH deposit/withdraw operations |
| `ERC7540Facet/`       | ERC-7540 async vault operations   |

### Library Prefixes

| Prefix        | Source                 |
| ------------- | ---------------------- |
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

**Rationale:** Zero slippage would disable protection, allowing arbitrarily bad trades by compromised allocators.

---

## Rate Limit Key Generation

Rate limit keys combine a function identifier with contextual data via `keccak256`. This provides:

- Granular per-integration rate limiting
- Implicit whitelisting (only configured addresses work)
- Flexibility for future function signatures

### Key Construction Helpers

`RateLimitHelpers.sol` provides multiple helpers for different key patterns.

See [Rate Limits](./RATE_LIMITS.md#whitelisting-via-rate-limit-keys) for design rationale.

---

## Function Overloading in Facets

Function overloading is not recommended in facets. When a facet has overloaded functions (multiple functions with the same name but different parameter types), `Interface.func.selector` will not compile because Solidity cannot disambiguate which overload to use. Instead, you must manually specify the function signature string to get the selector, e.g., `bytes4(keccak256("func(address,uint256)"))`. This adds complexity to wiring and is easy to get wrong.

---

## Rate Limit Gate-Check Pattern

Some operations use a "gate-check" pattern where they verify a rate limit is configured (`maxAmount > 0`) without actually decreasing the rate limit. This serves as an implicit whitelist mechanism. Used by:

- `WSTETHFacet.claimWithdrawal`: checks `LIMIT_WSTETH_CLAIM_WITHDRAW.maxAmount > 0`
- `WEETHFacet.claimWithdrawal`: checks `makeAddressKey(LIMIT_WEETH_CLAIM_WITHDRAW, weethModule).maxAmount > 0`

The check is on a dedicated claim-side key. Configuring only the request-withdraw key is not sufficient. The `requestWithdraw` will succeed and queue shares with Lido/EtherFi, but `claimWithdrawal` will later revert with `WSTETHFacet/invalid-action` or `WEETHFacet/invalid-action` until the claim key is added.

---

## No Shared Facet Storage

Facets cannot access each other's ERC-7201 storage domains. Each facet's namespaced storage is private to that facet. Cross-facet communication happens exclusively through `ControllerSharedStorage`, which holds references shared by all facets (e.g., `proxy`, `rateLimits`, `accessControls`).

---

## maxSlippage Per-Facet

Shared concepts like `maxSlippage` are intentionally duplicated in each facet's own ERC-7201 storage domain rather than stored in a single shared location. This gives governance granular control over slippage tolerance per integration and avoids coupling facets to each other's storage.

---

## Storage Field Caching

When a storage field such as `$.proxy` or `$.rateLimits` is accessed two or more times within a function, it should be cached into a local variable to avoid repeated `SLOAD` operations. This is a gas optimization pattern used throughout the codebase.

---

## Hardcoded Selector Protection

The Beacon protects core function selectors from being overwritten by integration wiring. The internal function `_revertIfCallSelectorIsHardcoded` in `Beacon.sol` checks against a fixed list of selectors and reverts with `CallSelectorHardcoded(bytes4)` if a match is found. The protected selectors cover both Controller functions (`updateIntegrations`, `removeIntegrations`, `accessControls`, `beacon`, `proxy`, `rateLimits`) and shared enumeration functions (`integrations`, `getConfig`, `getConfigs`, `getDispatch`, `getDispatches`). This prevents accidental or malicious replacement of the Controller's own routing and admin functions at the Beacon level, before configs ever reach a Controller.

See [BEACON.md](./BEACON.md) for the full details on hardcoded selector protection.

---

## Beacon and Controller Versioning

The Beacon and Controller are tightly coupled through the hardcoded selector list. If a new explicit function is added to the Controller, its selector must also be added to the Beacon's `_revertIfCallSelectorIsHardcoded` check. Without this, a Beacon admin could wire an integration whose call selector collides with the new Controller function, making that function unreachable. This means Beacon and Controller contract upgrades must be coordinated: any change to the Controller's function signatures requires a matching Beacon update.
