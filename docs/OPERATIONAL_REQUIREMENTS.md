# Operational Requirements

This document describes operational requirements for deploying and managing integrations with PAU.

---

## Protocol Seeding Requirements

Certain protocols require initialization before PAU can safely interact with them.

### ERC-4626 Vault Seeding

**Requirement:** All ERC-4626 vaults **MUST** have initial burned shares.

| Aspect             | Details                                                              |
| ------------------ | -------------------------------------------------------------------- |
| **Purpose**        | Prevents rounding-based frontrunning attacks                         |
| **Implementation** | Initial shares must be minted and burned (sent to zero/dead address) |
| **Permanence**     | Burned shares must be unrecoverable                                  |

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

All ERC-20 tokens used with PAU must be:

| Requirement         | Rationale                                                  |
| ------------------- | ---------------------------------------------------------- |
| **Non-rebasing**    | Rebasing tokens cause accounting inconsistencies           |
| **≥6 decimals**     | Prevents precision loss in rate limit calculations         |
| **Standard ERC-20** | Non-standard implementations may cause unexpected behavior |

---

## Rate Limit Configuration

- Rate limits **must** be configured for each specific integration
- Unconfigured integrations will revert on interaction
- Rate limit keys act as a whitelist (see [Rate Limits](./RATE_LIMITS.md))

# Maple Deposits

Maple Finance pools have an impairment lifecycle where `unrealizedLosses` can rise while `totalAssets` remains unchanged. Deposits price shares using `convertToShares`, which uses gross `totalAssets`, while redemptions price shares using `convertToExitAssets`, which is decreased during impairment. Therefore, deposits and immediate redemptions will be subject to immediate losses on an impaired pool.

The `ERC4626Facet` does not check that `unrealizedLosses()` is zero on a Maple pool during the deposit flow, which can result in socializing pre-existing losses onto PAU through fresh deposits.

Governance (via a spell to set rate limits for deposits to such Maple Pools) should mitigate this risk as soon as unrealized losses are posted to a Maple pool.

---

## OTC Buffer Deployment

When deploying a new OTC buffer:

1. Deploy the `OTCBuffer` contract
2. **Critical:** `initialize` the contract to set up the access controls and set infinite allowance (`type(uint256).max`) to the `ALMProxy`
3. Configure the OTC buffer address in the controller
4. Set appropriate rate limits and slippage parameters

**Failure to set infinite allowance will cause OTC swap completions to fail.**

---

## Uniswap V3/V4 Pool Onboarding

### Asset Restrictions

Only pools with 1:1 assets should be onboarded:

- USDC/USDT ✓
- USDC/DAI ✓
- USDC/USDS ✓
- USDC/ETH ✗ (different underlying)
- USDC/WBTC ✗ (different underlying)

### Onboarding Process

1. Verify pool contains only whitelisted 1:1 stablecoins
2. Verify pool does not have dangerous hooks
3. Configure rate limits for the specific pool
4. Configure pool parameters (e.g. tick limits, TWAP seconds, etc.) for the specific pool
5. Set appropriate slippage parameters

---

## General Onboarding Process

1. **Verify protocol compatibility** with PAU requirements
2. **Configure rate limit keys** via governance
3. **Set safety parameters** if applicable
4. **Test on fork** before mainnet deployment
5. **Monitor initial operations** closely after deployment

---

## Monitoring Recommendations

| Integration        | Monitor                                               |
| ------------------ | ----------------------------------------------------- |
| **All**            | Rate limit utilization, transaction failures          |
| **Centrifuge**     | Pending async requests, cross-chain transfer status   |
| **CCTP/LayerZero** | Bridge confirmation times, stuck transfers            |
| **Curve**          | Pool price, virtual price                             |
| **ERC-4626**       | Exchange rate changes, share price manipulation       |
| **ERC-7540**       | Pending async deposit/redeem requests                 |
| **Ethena**         | Pending mint/burn operations, delegated signer status |
| **Maple**          | Pending redemption requests                           |
| **OTC**            | Outstanding swap amounts, recharge progress           |
| **UniswapV3**      | Pool price, position value                            |
| **UniswapV4**      | Pool price, position value                            |
| **weETH**          | Pending withdrawal NFTs, finalization delays          |
| **wstETH**         | Pending withdrawal requests, finalization delays      |
