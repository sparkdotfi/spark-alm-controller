# Code Implementation Notes

This document captures specific implementation decisions and behaviors that may not be immediately obvious from reading the code.

### Operational Requirement

Ensure Curve pools are seeded with initial liquidity before whitelisting them for ALM Controller operations.

---

## Error Message Prefixes

The codebase uses standardized error message prefixes to indicate the source contract:

| Prefix | Source |
|--------|--------|
| `MC/` | MainnetController or shared controller logic |
| `FC/` | ForeignController-specific logic |
| `RL/` | RateLimits contract |

---

## Rate Limit Key Generation

Rate limit keys are generated using `keccak256` hashes, typically combining:
- A function identifier
- An address (e.g., pool address, token address)

This approach allows:
- Flexibility in future function signatures
- Granular rate limiting per protocol/asset combination
- Consistent identification across controller versions

See `RateLimitHelpers.sol` for the key generation utilities.
