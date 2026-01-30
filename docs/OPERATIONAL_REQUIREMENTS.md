# Operational Requirements

This document describes operational requirements for deploying and managing integrations with the Spark ALM Controller.

---

## Protocol Seeding Requirements

Certain protocols require initial seeding/initialization before the ALM Controller can safely interact with them. These requirements prevent manipulation attacks that exploit empty or uninitialized state.

### ERC-4626 Vault Seeding

**Requirement:** All ERC-4626 vaults that are onboarded **MUST** have an initial burned shares amount.

| Aspect | Details |
|--------|---------|
| **Purpose** | Prevents rounding-based frontrunning attacks |
| **Implementation** | Initial shares must be minted and burned (sent to zero address or dead address) |
| **Permanence** | Burned shares must be unrecoverable - they cannot be removed at a later date |
| **Timing** | Must be done before whitelisting the vault for ALM Controller operations |

**Additional Protection:** Donation attacks are protected against with the `maxExchangeRate` mechanism.

**Attack Prevented:** Without burned shares, an attacker could:
1. Deposit minimal amount to get shares
2. Donate assets directly to vault to inflate share price
3. Exploit rounding when victim deposits to steal funds

### Curve Pool Seeding

**Requirement:** Curve pools must be seeded with initial liquidity before whitelisting for ALM Controller operations.

| Aspect | Details |
|--------|---------|
| **Purpose** | Prevents adding liquidity to unseeded pools which can lead to unfavorable exchange rates |
| **Technical Detail** | Unseeded Curve pools have `get_virtual_price() == 0`, causing division by zero |
| **Enforcement** | `CurveLib.addLiquidity` will revert when `get_virtual_price() == 0` |
| **Timing** | Pool must be seeded before configuring rate limit keys |

**Code Reference:** See `src/libraries/CurveLib.sol`:

```solidity
// Intentionally reverts when get_virtual_price() == 0 to prevent adding liquidity to unseeded pools
require(
    params.minLpAmount >= valueDeposited
        * params.maxSlippage
        / curvePool.get_virtual_price(),
    "MC/min-amount-not-met"
);
```

---

## Rate Limit Configuration

### General Requirements

- Rate limits **must** be configured for specific integrations (e.g., specific ERC-4626 vaults)
- Vaults/protocols without rate limits set will revert on interaction

**Security Note:** This whitelisting mechanism prevents relayers from interacting with arbitrary contracts.

### Withdrawal Dependencies

Withdrawals using the following functions require corresponding deposit rate limits:

| Withdrawal Function | Required Deposit Rate Limit |
|--------------------|----------------------------|
| `withdrawERC4626` | Non-zero deposit rate limit for same vault |
| `redeemERC4626` | Non-zero deposit rate limit for same vault |
| `withdrawAave` | Non-zero deposit rate limit for same aToken |

## Token Requirements

### ERC-20 Token Compatibility

All ERC-20 tokens used with the ALM Controller must be:

| Requirement | Rationale |
|-------------|-----------|
| **Non-rebasing** | Rebasing tokens would cause accounting inconsistencies |
| **Sufficient decimal precision** | Minimum 6 decimals recommended to avoid precision loss in rate limit calculations |
| **Standard ERC-20 compliance** | Non-standard implementations may cause unexpected behavior |

---

## OTC Buffer Deployment

When deploying a new OTC buffer:

1. Deploy the `OTCBuffer` contract
2. **Critical:** Set infinite allowance (`type(uint256).max`) to the `ALMProxy`
3. Configure the OTC buffer address in the controller
4. Set appropriate rate limits and slippage parameters

**Failure to set infinite allowance will cause OTC swap completions to fail.**

---

## Uniswap V4 Pool Onboarding

### Asset Restrictions

Only pools with 1:1 assets can be onboarded:
- USDC/USDT ✓
- USDC/DAI ✓
- USDC/USDS ✓
- USDC/ETH ✗ (different underlying)
- USDC/WBTC ✗ (different underlying)

### Onboarding Process

1. Verify pool contains only whitelisted 1:1 stablecoins
2. Configure rate limit key for the specific pool
3. Set appropriate slippage parameters

---

## Checklist: New Integration Onboardings

### ERC-4626 Vault

- [ ] Verify vault has burned shares (check share balance of zero/dead address)
- [ ] Verify `maxExchangeRate` protection is appropriate
- [ ] Configure deposit rate limit key
- [ ] Configure withdrawal rate limit key (can use same key)
- [ ] Set appropriate `maxSlippage` if applicable

### Curve Pool

- [ ] Verify pool is seeded (check `get_virtual_price() > 0`)
- [ ] Verify pool contains only whitelisted stablecoins
- [ ] Configure add liquidity rate limit key
- [ ] Configure swap rate limit key
- [ ] Set appropriate `maxSlippage`

### Uniswap V4 Pool

- [ ] Verify pool contains only 1:1 stablecoins
- [ ] Configure swap rate limit key
- [ ] Set appropriate `maxSlippage`

### OTC Exchange

- [ ] Deploy and configure OTC buffer
- [ ] Set infinite allowance to ALMProxy
- [ ] Configure exchange parameters in controller
- [ ] Set rate limits and slippage parameters
- [ ] Set appropriate recharge rate
