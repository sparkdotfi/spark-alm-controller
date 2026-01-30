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
| [Liquidity Operations](./docs/LIQUIDITY_OPERATIONS.md) | Curve, Uniswap V4, and OTC swap integrations |
| [Threat Model](./docs/THREAT_MODEL.md) | Attack vectors, trust assumptions, and security invariants |
| [Security](./docs/SECURITY.md) | Protocol considerations and audit information |
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

## License

AGPL-3.0-or-later
