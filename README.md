# Spark ALM Controller

![Foundry CI](https://github.com/marsfoundation/spark-alm-controller/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/marsfoundation/spark-alm-controller/blob/master/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

This repository contains the onchain components of the Spark Liquidity Layer. The system enables controlled interaction with various DeFi protocols while enforcing rate limits and maintaining custody of funds through the ALMProxy.

### Core Contracts

| Contract | Description |
|----------|-------------|
| `ALMProxy` | Proxy contract that holds custody of all funds and routes calls to external contracts |
| `MainnetController` | Controller for Ethereum mainnet operations (Sky allocation, PSM, CCTP bridging) |
| `ForeignController` | Controller for L2 operations (PSM, external protocols, CCTP bridging) |
| `RateLimits` | Enforces and manages rate limits on controller operations |
| `OTCBuffer` | Buffer contract for offchain OTC swap operations |

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](./docs/ARCHITECTURE.md) | System architecture, contract interactions, and permissions |
| [Rate Limits](./docs/RATE_LIMITS.md) | Rate limit design, calculations, and configuration |
| [Liquidity Operations](./docs/LIQUIDITY_OPERATIONS.md) | Curve, Uniswap V4, OTC, and PSM integrations |
| [weETH Integration](./docs/WEETH_INTEGRATION.md) | EtherFi weETH module architecture and withdrawal flow |
| [Threat Model](./docs/THREAT_MODEL.md) | Attack vectors, trust assumptions, and security invariants |
| [Security](./docs/SECURITY.md) | Protocol-specific considerations and audit information |
| [Operational Requirements](./docs/OPERATIONAL_REQUIREMENTS.md) | Seeding, configuration, and onboarding checklists |
| [Development](./docs/DEVELOPMENT.md) | Testing, deployment, and upgrade procedures |
| [Code Notes](./docs/CODE_NOTES.md) | Implementation details and design decisions |

## Quick Start

### Testing

```bash
forge test
```

### Deployments

Deploy commands follow the pattern: `make deploy-<domain>-<env>-<type>`

```bash
# Deploy full ALM system to Base production
make deploy-base-production-full

# Deploy controller to Mainnet production
make deploy-mainnet-production-controller

# Deploy full staging environment
make deploy-staging-full
```

See [Development Guide](./docs/DEVELOPMENT.md) for detailed instructions.

## Architecture Overview

The controller contract is the entry point for all calls. It checks rate limits and executes logic, performing multiple calls to the ALMProxy atomically.

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│     Relayer     │────▶│  MainnetController   │────▶│    ALMProxy     │
│   (External)    │     │  or ForeignController│     │ (Funds Custody) │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
                                   │                          │
                                   │                          │
                                   ▼                          ▼
                        ┌──────────────────┐       ┌────────────────────┐
                        │   RateLimits     │       │ External Protocols │
                        │   (State Store)  │       │  (Sky, PSM, etc.)  │
                        └──────────────────┘       └────────────────────┘
```

See [Architecture Documentation](./docs/ARCHITECTURE.md) for detailed diagrams and explanations.

## Max Slippages

Max slippage values throughout ALM controller integrations are defined as how close the resulting value should be to the expected or minimum value, **not** as how much deviation is allowed. This is an inverse way of denoting max slippages compared to common DeFi nomenclature.

### How It Works

In common DeFi terminology, a 0.1% max slippage typically means the resulting value can be 0.1% away from the expected or spot rate/value. However, throughout this codebase, such an expectation would be denoted as a max slippage of 99.9% (or 0.999e18 when scaled).

### Historical Context

The reason for this inverse notation is to allow a max slippage of 0 (the unset default value for any storage slot) to imply that the integration is disabled, instead of 0 implying "no slippage allowed". This design choice means that:

- A value of 0 indicates the integration is disabled
- Non-zero values represent the minimum acceptable ratio of actual result to expected result

### Value Scaling

All max slippage values are scaled to 1e18, meaning:

- `0.999e18` represents a "max slippage" of 99.9%, which means the resulting price, rate, or value must be **at least** 99.9% of the expected price, rate, or value
- `0.995e18` represents 99.5%, meaning the result must be at least 99.5% of the expected value
- `1e18` represents 100%, meaning no slippage is allowed (result must equal expected value)

### UniswapV4 Integration

Particularly for the UniswapV4 integration, since the pools being interacted with are assumed to pair 1:1 stablecoins (i.e., USDT and USDC), the max slippage defines how close to a 1.0 price the swap is allowed to be. For example:

- A max slippage of `0.999e18` means the swap out value must be at least $0.999 for each $1.00 of input value.
- A max slippage of `0.995e18` means the swap out value must be at least $0.995 for each $1.00 of input value.

## Security

### Key Trust Assumptions

- **`DEFAULT_ADMIN_ROLE`**: Fully trusted, run by governance
- **`RELAYER`**: Assumed compromisable - logic prevents unauthorized value movement
- **`FREEZER`**: Can stop compromised relayers via `removeRelayer`

See [Security Documentation](./docs/SECURITY.md) for complete trust assumptions and mitigations.

### Audits

Audit reports are available in the [`audits/`](./audits/) directory. The system has been audited by:
- Cantina
- ChainSecurity
- Certora

---

<p align="center">
  <img src="https://github.com/user-attachments/assets/c83ef7e4-fae1-4c5c-8cff-99494ef75962" height="100"/>
</p>
