# Security

This document describes protocol-specific security considerations for PAU.

## Trust Assumptions

### Role Trust Levels

| Role                 | Trust Level               | Description                                                                                                       |
| -------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | **Fully trusted**         | Run by governance                                                                                                 |
| `ALLOCATOR_ROLE`     | **Assumed compromisable** | Logic must prevent unauthorized value movement. This should be a major consideration during auditing engagements. |
| `FREEZER_ROLE`       | Trusted                   | Can stop compromised allocators via `removeAllocator`                                                             |

### Allocator Compromise Mitigations

When assuming a compromised `ALLOCATOR`:

1. **Value movement restrictions:** Smart contract logic must prevent movement of value outside the PAU system of contracts
    - Exception: Asynchronous integrations (e.g., BUIDL) where `transferAsset` sends funds to whitelisted addresses, with LP tokens minted asynchronously, or OTC trades.

2. **Loss limitations:** Any action must be limited to "reasonable" slippage/losses/opportunity cost by rate limits

3. **Emergency response:** The `FREEZER_ROLE` must be able to stop harmful actions within max rate limits using `removeAllocator`

4. **DOS attacks:** A compromised allocator can perform DOS attacks. Recovery procedures are outlined in `Attacks.t.sol` test files.

For comprehensive threat modeling, attack vectors, and trust assumptions, see [Threat Model](./THREAT_MODEL.md).

---

## Protocol-Specific Considerations

### Ethena Integration

**Trust Assumption:** Ethena is a trusted counterparty in this system.

**Scenario:** An operation initiated by a allocator can continue after a freeze is performed.

**Implication:** If the `FREEZER_ROLE` role removes a allocator while an Ethena mint/burn operation is pending, that operation will still complete.

**Rationale:**

- Ethena operations are asynchronous by design
- The delegated signer role provides sufficient safeguards (trusted to not honor requests with >50bps slippage)
- Ethena's API [Order Validity Checks](https://docs.ethena.fi/solution-design/minting-usde/order-validity-checks) provide protection against malicious delegated signers
- Worst-case loss is bounded by slippage limits and rate limits on the operation

**Security Note:** The delegated signer role can technically be set by a compromised allocator. Ethena's off-chain validation is trusted to prevent abuse in this scenario.

### EtherFi/weETH Integration

**Trust Assumption:** EtherFi is trusted to eventually process withdrawal requests.

**Risk:** Withdrawal requests can be invalidated by EtherFi admin without returning funds, but can also be revalidated.

**Architecture Note:** The weETH integration requires a dedicated `WEETHModule` contract to handle withdrawal NFTs and ETH conversion. See [weETH Integration](./WEETH_INTEGRATION.md) for details.

### OTC Desk Integration

**Trust Assumption:** All whitelisted exchanges/OTC desks will complete trades (no counterparty risk beyond slippage).

**Maximum Loss:** Bounded by single outstanding OTC swap amount per exchange.

See [Liquidity Operations](./LIQUIDITY_OPERATIONS.md) for OTC mechanics.

### Centrifuge Integration

**Architecture Note:** Each Centrifuge cancel and claim-cancel path is gated by its own dedicated rate-limit key, each presence-checked via `_requireRateLimitExists`. Every key must be configured by governance before the corresponding path can be used.

**Security Node:** If a cancel key is set but its matching claim-cancel key is not, `cancel*Request` will succeed and `claimCancel*Request` will then revert. Because Centrifuge requests use `REQUEST_ID = 0`, no new deposit or redeem request can be submitted while a cancellation is pending, so the integration stays stuck until governance configures the missing claim-cancel key.

---

## Governance and Emergency Controls

### ETH Recovery Mechanism

**Guarantee:** Any ETH left in the `ALMProxy` can always be removed.

| Method                              | Access       | Description                                                              |
| ------------------------------------| ------------ | ------------------------------------------------------------------------ |
| `ALMProxy.doCallWithValue`          | `CONTROLLER` | Allows arbitrary calls with ETH value attached from `ALMProxy`.          |
| `ALMProxyFreezable.doCallWithValue` | `RELAYER`    | Allows arbitrary calls with ETH value attached from `ALMProxyFreezable`. |
| `wrapAll`                           | `RELAYER`    | Wraps all ETH in `ALMProxy` to WETH (via `WrapProxyETHFacet`).           |

**Use Cases:**

- Recover accidentally sent ETH
- Withdraw ETH received from protocol operations
- Convert ETH to WETH for standard token handling
- Emergency fund extraction

**Security:**

- `ALMProxy.doCallWithValue` is gated by the `CONTROLLER` role, which is held only by the `Controller` contract. A compromised relayer can therefore only reach this function indirectly through facets wired into the `Controller`, where rate limits and per-facet logic apply.
- `ALMProxyFreezable.doCallWithValue` is gated by the `RELAYER` role directly and is callable by a compromised relayer. `ALMProxyFreezable` is not intended to hold funds, and the `FREEZER` role can revoke a compromised relayer via `removeRelayer` to halt further calls.
- `wrapAll` is relayer-accessible but only converts ETH to WETH within the `ALMProxy`, keeping funds in the system.

---

## Audit Considerations

### Gas Fee Losses

**Stated Assumption:** Gas fee losses are ignored for security audit purposes.

**Rationale:**

- Gas fees are operational costs, not security vulnerabilities
- Gas fee griefing by a compromised allocator is bounded by block production and MEV considerations
- Economic impact is minimal compared to rate-limited capital protection

**Implication:** Audits should focus on capital preservation and rate limit effectiveness.

---

## Operational Requirements

For detailed operational requirements including seeding, configuration, and onboarding checklists, see [Operational Requirements](./OPERATIONAL_REQUIREMENTS.md).

### Beacon Governance Surface

The Beacon manages all integration configurations (facet addresses and selector wiring) for every Controller that references it. Only the `DEFAULT_ADMIN_ROLE` on the Beacon can call `setIntegration` or `removeIntegration`. This is a critical security boundary: if a malicious integration were configured, the facet would gain arbitrary access to Controller storage and ALMProxy funds via `delegatecall`. The Beacon validates that facet addresses are non-zero and have deployed code, and protects hardcoded selectors from being overwritten. Auditors should verify that no path exists to bypass these validations, and that the admin-only gate on integration management cannot be circumvented.

---

## Audits

Audit reports are available in the [`audits/`](../audits/) directory. The system has been audited by:

- Cantina
- ChainSecurity
- Certora
- Unvariant

Each version release includes corresponding audit reports from these security firms.
