# Development

This document covers development workflows including testing, deployment, and upgrade procedures.

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

## Deployments

All deployment commands follow the nomenclature: `make deploy-<domain>-<env>-<type>`

### Examples

| Command | Description |
|---------|-------------|
| `make deploy-base-production-full` | Deploy full ALM system to Base production |
| `make deploy-mainnet-production-controller` | Deploy controller to Mainnet production |
| `make deploy-staging-full` | Deploy full staging environment with new allocation system and dependencies |

### Deployment Types

- **full** - Complete ALM system deployment
- **controller** - Controller contract only

### Environments

- `production` - Production deployment
- `staging` - Staging/testing deployment

---

## Staging Upgrade Simulations

To perform upgrades against forks of mainnet and base for testing/simulation purposes:

### 1. Set Up Forked Anvil Nodes

Start three anvil nodes forked against different networks:

**Mainnet:**
```bash
anvil --fork-url $MAINNET_RPC_URL
```

**Base:**
```bash
anvil --fork-url $BASE_RPC_URL -p 8546
```

**Arbitrum:**
```bash
anvil --fork-url $ARBITRUM_ONE_RPC_URL -p 8547
```

### 2. Point to Local RPCs

```bash
export MAINNET_RPC_URL=http://127.0.0.1:8545
export BASE_RPC_URL=http://127.0.0.1:8546
export ARBITRUM_ONE_RPC_URL=http://127.0.0.1:8547
```

### 3. Upgrade Mainnet Contracts

Impersonate the `SPARK_PROXY`:

```bash
export SPARK_PROXY=0x3300f198988e4C9C63F75dF86De36421f06af8c4

cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_setBalance $SPARK_PROXY `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$MAINNET_RPC_URL" anvil_impersonateAccount $SPARK_PROXY

ENV=production \
OLD_CONTROLLER=0xb960F71ca3f1f57799F6e14501607f64f9B36F11 \
NEW_CONTROLLER=0x5cf73FDb7057E436A6eEaDFAd27E45E7ab6E431e \
forge script script/Upgrade.s.sol:UpgradeMainnetController --broadcast --unlocked --sender $SPARK_PROXY
```

### 4. Upgrade Base Contracts

Impersonate the `SPARK_EXECUTOR`:

```bash
export SPARK_EXECUTOR=0xF93B7122450A50AF3e5A76E1d546e95Ac1d0F579

cast rpc --rpc-url="$BASE_RPC_URL" anvil_setBalance $SPARK_EXECUTOR `cast to-wei 1000 | cast to-hex`
cast rpc --rpc-url="$BASE_RPC_URL" anvil_impersonateAccount $SPARK_EXECUTOR

CHAIN=base \
ENV=production \
OLD_CONTROLLER=0xc07f705D0C0e9F8C79C5fbb748aC1246BBCC37Ba \
NEW_CONTROLLER=0x5F032555353f3A1D16aA6A4ADE0B35b369da0440 \
forge script script/Upgrade.s.sol:UpgradeForeignController --broadcast --unlocked --sender $SPARK_EXECUTOR
```

---

## Rate Limit Verification

See [RATE_LIMITS.md](./RATE_LIMITS.md#rate-limit-uses) for instructions on running the Wake printer to verify rate limit configurations.

---

## Project Structure

```
spark-alm-controller/
├── audits/           # Security audit reports
├── deploy/           # Deployment helper contracts
├── docs/             # Documentation
├── lib/              # Dependencies (git submodules)
├── printers/         # Wake printer scripts
├── script/           # Deployment and upgrade scripts
├── src/              # Source contracts
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
- Use meaningful error messages with contract prefixes (e.g., `"MC/invalid-indices"`)
