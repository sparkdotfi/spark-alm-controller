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

**Guarantee:** Any ETH left in the ALMProxy can always be removed.

| Method | Access | Description |
|--------|--------|-------------|
| `doCallWithValue` | `DEFAULT_ADMIN_ROLE` (governance) | Allows arbitrary calls with ETH value attached from ALMProxy |
| `wrapAllProxyETH` | `RELAYER` | Wraps all ETH in ALMProxy to WETH (MainnetController only) |

**Use Cases:**
- Recover accidentally sent ETH
- Withdraw ETH received from protocol operations
- Convert ETH to WETH for standard token handling
- Emergency fund extraction

**Security:** The `doCallWithValue` function is governance-controlled and does not introduce attack vectors for compromised relayers. The `wrapAllProxyETH` function is relayer-accessible but only converts ETH to WETH within the ALMProxy, keeping funds in the system.

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

For detailed operational requirements including:
- ERC-4626 vault seeding
- Curve pool seeding
- Token requirements
- Rate limit configuration
- Onboarding checklists

See [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md).

---

## Threat Model

For a comprehensive threat model including:
- Attack vectors and mitigations
- Security invariants
- Audit focus areas

See [Threat Model](./THREAT_MODEL.md).

---

## Audits

Audit reports are available in the [`audits/`](../audits/) directory. The system has been audited by:

- Cantina
- ChainSecurity
- Certora

Each version release includes corresponding audit reports from these security firms.
