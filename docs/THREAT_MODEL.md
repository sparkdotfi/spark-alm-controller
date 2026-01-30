# Threat Model

This document outlines the threat model for the Spark ALM Controller, including attack vectors, trust assumptions, and mitigations.

## Actors and Trust Levels

| Actor | Trust Level | Description |
|-------|-------------|-------------|
| **Governance** (`DEFAULT_ADMIN_ROLE`) | Fully trusted | Controls all admin functions, can upgrade controllers, set rate limits |
| **Relayer** (`RELAYER`) | **Untrusted** | Assumed to be potentially compromised at any time |
| **Freezer** (`FREEZER`) | Trusted | Emergency response role, can remove compromised relayers |
| **External Protocols** | Varies | Trust depends on specific integration (see Protocol Trust section) |

---

## Primary Threat: Compromised Relayer

The system is designed with the assumption that a `RELAYER` can be fully compromised by a malicious actor. This is the primary threat the architecture defends against.

### Attack Vectors

| Attack | Mitigation |
|--------|------------|
| **Unauthorized fund transfer** | Funds can only move to whitelisted addresses; rate limits bound exposure |
| **Excessive slippage attacks** | `maxSlippage` parameters enforce minimum acceptable returns |
| **Rate limit exhaustion** | Rate limits regenerate over time; bounded maximum exposure |
| **Interaction with malicious contracts** | Rate limit keys act as whitelist - only configured integrations work |
| **DOS attacks** | Accepted risk; recovery procedures documented in `Attacks.t.sol` |
| **Gas griefing** | Accepted risk; economic impact is minimal compared to rate-limited capital |

### Design Principles

1. **Value cannot leave the system** - All operations must keep funds within the ALM system of contracts
   - Exception: Asynchronous integrations (e.g., BUIDL, Ethena) where funds go to whitelisted addresses

2. **Losses bounded by rate limits** - Any single attack is limited to the current rate limit capacity

3. **Freezer can halt attacks** - The `FREEZER` role can remove a compromised relayer within the rate limit window

4. **No trust in relayer input** - All relayer-provided parameters are validated against on-chain constraints

---

## Rate Limits as Security Boundary

Rate limits serve as the primary security boundary against compromised relayers:

### How Rate Limits Protect

- **Immediate attack capacity** = `lastAmount` (current available limit)
- **Maximum attack capacity** = `maxAmount` (rate limit ceiling)
- **Recovery rate** = `slope` (tokens per second regeneration)

### Rate Limit Key Whitelisting

Rate limit keys (hash of function identifier + address) act as an implicit whitelist:
- Only governance-configured integrations have valid rate limit keys
- Attempting to use unconfigured addresses will revert
- Provides protection against interaction with malicious contracts

---

## Protocol-Specific Trust

### Fully Trusted Protocols

| Protocol | Trust Reason |
|----------|--------------|
| **Sky Allocation System** | Core protocol, governance controlled |
| **PSM** | Core protocol, immutable |

### Trusted with Caveats

| Protocol | Trust Level | Caveat |
|----------|-------------|--------|
| **Ethena** | Trusted counterparty | Delegated signer role can be set by relayer; Ethena's off-chain validation trusted to prevent abuse |
| **EtherFi** | Trusted | Withdrawal requests can be invalidated by EtherFi admin |
| **OTC Desks** | Trusted counterparties | Assumed to complete trades; max loss bounded by single swap amount |
| **Maple** | Trusted | Permissioned pools with slower dynamics |

### External Protocol Risks

| Protocol | Risk | Mitigation |
|----------|------|------------|
| **ERC-4626 Vaults** | Rounding attacks, donation attacks | Require burned shares; maxExchangeRate mechanism |
| **Curve Pools** | Unseeded pool manipulation | Require pools to be seeded before whitelisting |
| **CCTP** | Bridge delays | Operational consideration only |

---

## Attack Scenarios and Responses

### Scenario 1: Relayer Key Compromise

**Attack:** Attacker gains access to relayer private key

**Response:**
1. `FREEZER` calls `removeRelayer` to revoke access
2. System switches to backup relayer
3. Maximum loss bounded by rate limits at time of compromise

### Scenario 2: Repeated High-Slippage Transactions

**Attack:** Compromised relayer repeatedly executes trades at maximum allowed slippage

**Response:**
1. Rate limits bound total value extracted
2. `FREEZER` removes relayer when attack detected
3. Slippage parameters limit per-transaction loss

### Scenario 3: DOS Attack

**Attack:** Compromised relayer spams transactions to prevent legitimate operations

**Response:**
1. Accept temporary operational disruption
2. `FREEZER` removes compromised relayer
3. Resume operations with backup relayer
4. Recovery procedures documented in `Attacks.t.sol`

### Scenario 4: Malicious Contract Interaction Attempt

**Attack:** Compromised relayer tries to interact with malicious contract

**Response:**
1. Rate limit key not configured for malicious contract
2. Transaction reverts automatically
3. No funds at risk

---

## Assets NOT Considered Threats

| Item | Rationale |
|------|-----------|
| **Gas costs** | Operational expense, not security vulnerability |
| **Temporary DOS** | Acceptable; recovery procedures exist |
| **Slippage within limits** | Bounded by configuration; operational cost |

---

## Security Invariants

The following invariants must always hold:

1. **Funds stay in system** - ALMProxy balance can only decrease through governance-approved operations
2. **Rate limits enforced** - No operation can exceed its configured rate limit
3. **Whitelist enforced** - Only configured addresses can be interacted with
4. **Freezer can halt** - `FREEZER` can always remove any relayer
5. **Governance supreme** - `DEFAULT_ADMIN_ROLE` can always recover funds and reconfigure system

---

## Audit Focus Areas

When auditing, focus on:

1. **Rate limit bypass** - Can any path avoid rate limit checks?
2. **Whitelist bypass** - Can unconfigured addresses be used?
3. **Fund extraction** - Can funds leave the ALM system unexpectedly?
4. **Slippage manipulation** - Can `maxSlippage` checks be bypassed?
5. **Access control** - Are role checks correctly implemented?

Do NOT focus on:
- Gas optimization (unless it affects security)
- DOS prevention (accepted risk, but still preferable to be mitigated if possible)
- Theoretical attacks requiring governance compromise
