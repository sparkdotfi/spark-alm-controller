# Development

This document covers development workflows and testing.

## Prerequisites

This project uses [Foundry](https://getfoundry.sh/) for development and testing.

## Testing

Run all tests:

```bash
forge test
```

### Attack Simulation Tests

DOS attack scenarios and recovery procedures are documented in `Attacks.t.sol` test files located in the `test/` directory.

---

## Rate Limit Verification

See [RATE_LIMITS.md](./RATE_LIMITS.md#rate-limit-uses) for instructions on running the Wake printer to verify rate limit configurations.

---

## Project Structure

```
diamond-pau/
├── audits/           # Security audit reports
├── docs/             # Documentation
├── lib/              # Dependencies (git submodules)
├── printers/         # Wake printer scripts
├── src/              # Source contracts
│   ├── facets/       # Protocol integration facets
│   ├── interfaces/   # Contract interfaces
│   └── libraries/    # Library contracts
└── test/             # Test files
```

---

## Code Style

This project follows standard Solidity conventions. Key points:

- Use explicit visibility modifiers
- Follow the Checks-Effects-Interactions pattern
- Document all external/public functions with NatSpec
- Use meaningful error messages with contract/facet prefixes (e.g., `"CurveFacet/invalid-indices"`, `"Controller/invalid-dispatch"`)
