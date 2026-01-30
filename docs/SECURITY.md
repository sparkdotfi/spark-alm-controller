# Security

This document describes security considerations, trust assumptions, and attack mitigations for the Spark ALM Controller.

## Trust Assumptions

### Role Trust Levels

| Role | Trust Level | Description |
|------|-------------|-------------|
| `DEFAULT_ADMIN_ROLE` | **Fully trusted** | Run by governance |
| `RELAYER` | **Assumed compromisable** | Logic must prevent unauthorized value movement. This should be a major consideration during auditing engagements. |
| `FREEZER` | Trusted | Can stop compromised relayers via `removeRelayer` |

### Relayer Compromise Mitigations

When assuming a compromised `RELAYER`:

1. **Value movement restrictions:** Smart contract logic must prevent movement of value outside the ALM system of contracts
   - Exception: Asynchronous integrations (e.g., BUIDL) where `transferAsset` sends funds to whitelisted addresses, with LP tokens minted asynchronously

2. **Loss limitations:** Any action must be limited to "reasonable" slippage/losses/opportunity cost by rate limits

3. **Emergency response:** The `FREEZER` must be able to stop harmful actions within max rate limits using `removeRelayer`

4. **DOS attacks:** A compromised relayer can perform DOS attacks. Recovery procedures are outlined in `Attacks.t.sol` test files.

---

## Protocol-Specific Considerations

### Ethena Integration

**Trust Assumption:** Ethena is a trusted counterparty in this system.

**Scenario:** An operation initiated by a relayer can continue after a freeze is performed.

**Implication:** If the `FREEZER` role removes a relayer while an Ethena mint/burn operation is pending, that operation will still complete.

**Rationale:**
- Ethena operations are asynchronous by design
- Ethena's API [Order Validity Checks](https://docs.ethena.fi/solution-design/minting-usde/order-validity-checks) provide protection against malicious delegated signers
- Worst-case loss is bounded by slippage limits and rate limits on the operation

**Security Note:** The delegated signer role can technically be set by a compromised relayer. Ethena's off-chain validation is trusted to prevent abuse in this scenario.

### EtherFi Integration

Request for withdrawal of funds can be invalidated by admin of EtherFi without returning the funds, but can also be revalidated again.

---

## Governance and Emergency Controls

### ETH Recovery Mechanism

**Guarantee:** Any ETH left in the ALMProxy can always be removed by governance through a `doCallWithValue` operation.

| Aspect | Details |
|--------|---------|
| **Implementation** | The `doCallWithValue` function in ALMProxy allows arbitrary calls with ETH value attached |
| **Access Control** | Only addresses with `DEFAULT_ADMIN_ROLE` (governance) can call this function |

**Use Cases:**
- Recover accidentally sent ETH
- Withdraw ETH received from protocol operations
- Emergency fund extraction

**Security:** Since this is governance-controlled, it does not introduce additional attack vectors for compromised relayers.

---

## Asset Assumptions

### 1:1 Asset Parity

**Assumption:** All assets are tracking the same underlying. The system handles only USD stablecoins, with values treated as equivalent (i.e., 1 USDT = 1 USDC).

**Risk:** If assets depeg significantly from each other, the 1:1 assumption breaks down. This is an accepted protocol risk that should be monitored operationally.

---

## Security and Audit Considerations

### Gas Fee Losses

**Stated Assumption:** Gas fee losses are ignored for the purposes of audits and security considerations.

**Rationale:**
- Gas fees are operational costs, not security vulnerabilities
- Gas fee griefing by a compromised relayer is bounded by the relayer's ability to submit transactions (rate-limited by block production and MEV considerations)
- The economic impact of gas fee griefing is significantly lower than the value protection provided by rate limits on capital movements

**Implication:** Audits should focus on capital preservation and rate limit effectiveness rather than gas optimization when evaluating security.

**Operational Consideration:** Gas costs should still be monitored and optimized from an operational efficiency perspective, but they are not considered a security risk vector.

---

## Operational Requirements

### ERC-4626 Vaults

All ERC-4626 vaults that are onboarded **MUST** have an initial burned shares amount that prevents rounding-based frontrunning attacks. These shares must be unrecoverable so they cannot be removed at a later date. Donation attacks are also protected against with the maxExchangeRate mechanism.

### ERC-20 Tokens

All ERC-20 tokens are to be:
- Non-rebasing
- With sufficiently high decimal precision (>= 6 decimals)

### Rate Limit Configuration

- Rate limits must be configured for specific ERC-4626 vaults and AAVE aTokens
- Vaults without rate limits set will revert
- Unlimited rate limits can be used as an onboarding tool

### Withdrawal Dependencies

Withdrawals using `withdrawERC4626`/`redeemERC4626`/`withdrawAave` must always have a non-zero deposit rate limit set for their corresponding deposit functions in order to succeed.

---

## Audits

Audit reports are available in the [`audits/`](../audits/) directory. The system has been audited by:

- Cantina
- ChainSecurity
- Certora

Each version release includes corresponding audit reports from these security firms.
