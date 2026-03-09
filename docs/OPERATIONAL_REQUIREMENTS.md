# Operational Requirements

This document describes operational requirements for deploying and managing integrations with the Spark ALM Controller.

---

## Protocol Seeding Requirements

Certain protocols require initialization before the ALM Controller can safely interact with them.

### ERC-4626 Vault Seeding

**Requirement:** All ERC-4626 vaults **MUST** have initial burned shares.

| Aspect | Details |
|--------|---------|
| **Purpose** | Prevents rounding-based frontrunning attacks |
| **Implementation** | Initial shares must be minted and burned (sent to zero/dead address) |
| **Permanence** | Burned shares must be unrecoverable |

**Additional Protection:** Donation attacks are protected against with the `maxExchangeRate` mechanism.

**Attack Prevented:** Without burned shares, an attacker could:
1. Deposit minimal amount to get shares
2. Donate assets directly to vault to inflate share price
3. Exploit rounding when victim deposits to steal funds

### Curve Pool Seeding

**Requirement:** Curve pools must be seeded with initial liquidity before use. Seeding must be done to an unrecoverable address (e.g, address(1)). This will prevent any unintended behaviours.

### Uniswap V4 Pool Seeding

**Requirement:** Uniswap V4 pools must be seeded with initial liquidity before use. Seeding must be done to an unrecoverable address (e.g, address(1)). This will prevent any unintended behaviours.


---

## Token Requirements

All ERC-20 tokens used with the ALM Controller must be:

| Requirement | Rationale |
|-------------|-----------|
| **Non-rebasing** | Rebasing tokens cause accounting inconsistencies |
| **≥6 decimals** | Prevents precision loss in rate limit calculations |
| **Standard ERC-20** | Non-standard implementations may cause unexpected behavior |

---

## Rate Limit Configuration

- Rate limits **must** be configured for each specific integration
- Unconfigured integrations will revert on interaction
- Rate limit keys act as a whitelist (see [Rate Limits](./RATE_LIMITS.md))

### Withdrawal Dependencies

| Withdrawal Function | Required |
|--------------------|----------|
| `withdrawERC4626` | Non-zero deposit rate limit for same vault |
| `redeemERC4626` | Non-zero deposit rate limit for same vault |
| `withdrawAave` | Non-zero deposit rate limit for same aToken |

---

## OTC Buffer Deployment

When deploying a new OTC buffer:

1. Deploy the `OTCBuffer` contract
2. **Critical:** `initialize` the contract to set up the access controls and set infinite allowance (`type(uint256).max`) to the `ALMProxy`
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
2. Verify pool does not have dangerous hooks
3. Configure rate limits for the specific pool
4. Configure tick limits for the specific pool
5. Set appropriate slippage parameters

---

## General Onboarding Process

1. **Verify protocol compatibility** with ALM Controller requirements
2. **Configure rate limit keys** via governance
3. **Set safety parameters** if applicable
4. **Test on fork** before mainnet deployment
5. **Monitor initial operations** closely after deployment

---

## Monitoring Recommendations

| Integration | Monitor |
|-------------|---------|
| **All** | Rate limit utilization, transaction failures |
| **UniswapV4** | Pool price |
| **ERC-4626** | Exchange rate changes, share price manipulation |
| **OTC** | Outstanding swap amounts, recharge progress |
| **weETH** | Pending withdrawal NFTs, finalization delays |
| **CCTP/LayerZero** | Bridge confirmation times, stuck transfers |
| **Ethena** | Pending mint/burn operations, delegated signer status |
