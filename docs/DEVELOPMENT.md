# Development

This document covers development workflows and testing.

## Prerequisites

This project uses [Foundry](https://getfoundry.sh/) for development and testing. Solidity version is `^0.8.34`.

## Testing

Run all tests:

```bash
forge test
```

### Attack Simulation Tests

DOS attack scenarios and recovery procedures are documented in `Attacks.t.sol` test files located in the `test/` directory.

---

## Project Structure

```
diamond-pau/
├── audits/           # Security audit reports
├── docs/             # Documentation
├── lib/              # Dependencies (git submodules)
├── src/              # Source contracts
│   ├── ALMProxy.sol
│   ├── ALMProxyFreezable.sol
│   ├── AccessControls.sol
│   ├── Beacon.sol
│   ├── Controller.sol
│   ├── ControllerSharedStorage.sol
│   ├── PAUFactory.sol
│   ├── RateLimits.sol
│   ├── facets/       # Protocol integration facets
│   ├── interfaces/   # Contract interfaces
│   └── libraries/    # Shared libraries (ApproveLib, RateLimitHelpers)
└── test/             # Test files
    ├── avalanche-fork/ # Avalanche fork tests
    ├── base-fork/    # Base fork tests
    ├── integration/  # Facet integration tests
    ├── interfaces/   # Test interfaces (IMainnetControllerFull, etc.)
    ├── mainnet-fork/ # Mainnet fork tests
    ├── mocks/        # Mock contracts
    └── unit/         # Unit tests
```

---

## Code Style

This project follows standard Solidity conventions. Key points:

- Use explicit visibility modifiers
- Follow the Checks-Effects-Interactions pattern
- Document all external/public functions with NatSpec
- Use meaningful error messages with the format `"ComponentName/error-description"` for require strings (e.g., `"CurveFacet/invalid-indices"`, `"Controller/invalid-dispatch"`). Custom errors (e.g., `error InvalidFacet(address)`) are preferred for new code.

### Diamond Architecture Conventions

#### Block Comment Section Headers

Contracts use block comment headers to organize code into sections:

```solidity
/**********************************************************************************************/
/*** Section Name                                                                           ***/
/**********************************************************************************************/
```

Standard sections in order (varies by contract type): Constants, Facet Storage Domain (or Controller Storage Domain), Constructor, External Interactive Admin Functions, External Interactive Relayer Functions, External Variable Getters, External View/Pure Functions, Internal Interactive Functions, Internal View/Pure Functions. Some contracts also include Modifiers and Fallback Functions sections.

#### Event Naming

Events are prefixed with the facet domain name (e.g., `AaveMaxSlippageSet`, `UniswapV4MaxSlippageSet`, `CCTPTransferInitiated`).

#### Parameter Order Must Match

In the diamond dispatch pattern, only the 4-byte function selector is swapped. The remaining calldata (parameters) is forwarded unchanged. Therefore, parameter order in the facet function must exactly match the expected call interface. Mismatched order causes silent ABI decoding errors.

#### Config After Wiring

Configuration calls (e.g., `setMaxSlippage`) are dispatched through the Controller like any other facet call. They must come after `beacon.setIntegration()` and `controller.updateIntegrations()` since the dispatch route does not exist until the integration is synced.

#### Cleanup Over Wiring

When modifying test bases, remove unused setup rather than wiring additional facets that are not needed for the test.

#### View Functions for Immutables

All immutable state variables in facets should be exposed via view functions in the facet's interface for ABI accessibility.

#### Named Mappings

Use Solidity 0.8.26+ named mapping syntax for readability, e.g., `mapping(address pool => uint256 maxSlippage) maxSlippages`.

#### ERC-7201 Storage Naming

Each facet uses generic internal names for its storage: `FacetStorage` (struct), `FACET_STORAGE_LOCATION` (constant), `_getFacetStorage()` (accessor). The ERC-7201 namespace follows the pattern `sky.pau.storage.<FacetName>`, where `<FacetName>` must match both the contract name and the file name (e.g., `AaveFacet.sol` contains `contract AaveFacet` with namespace `sky.pau.storage.AaveFacet`).

#### Reentrancy Guard and Event Ordering

All external facet functions must use the `nonReentrant` modifier as a standard practice. Events should be emitted at the end of the function, after all state changes and external calls are complete.

#### UUPS for Auxiliary Contracts

Auxiliary contracts (OTCBuffer, WEETHModule) use the UUPS upgrade pattern. Facets themselves use immutable constructor parameters and are not upgradeable.

