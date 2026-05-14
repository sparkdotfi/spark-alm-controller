# Beacon

This document describes the `Beacon` contract, the single source of truth for all integration configurations in the DiamondPAU system.

## Purpose

The Beacon centralizes integration management. It holds the canonical mapping of integration IDs to their configurations (facet address + wire definitions) and the hot-path dispatch lookup (call selector to facet + delegate selector). Multiple Controllers can reference the same Beacon, and each Controller syncs its local copy of configs via `updateIntegrations`.

## Data Structures

The Beacon uses three storage structures defined in `IEnumerableIntegrations`:

| Struct        | Fields                                           | Description                                                                        |
| ------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `Config`      | `address facet`, `Wire[] wires`                  | A facet address and its array of selector mappings                                 |
| `Wire`        | `bytes4 callSelector`, `bytes4 delegateSelector` | Maps an incoming selector to the selector that will be delegatecalled on the facet |
| `Dispatch`    | `address facet`, `bytes4 delegateSelector`       | Hot-path lookup entry for a single call selector                                   |
| `Integration` | `bytes32 id`, `Config config`                    | An integration ID paired with its config (used by `integrations()`)                |

### Storage Layout

- `EnumerableSet.Bytes32Set _integrationIds`: Tracks all configured integration IDs for enumeration
- `mapping(bytes32 => Config) _configs`: Per-integration configuration
- `mapping(bytes4 => Dispatch) _dispatches`: Selector-to-facet lookup used for collision detection

## Access Control

The Beacon uses OpenZeppelin `AccessControlEnumerable`. Only `DEFAULT_ADMIN_ROLE` can call `setIntegration` and `removeIntegration`. Both functions are also protected by `nonReentrant`.

## Integration Lifecycle

### Setting an Integration

`setIntegration(bytes32 id, Config calldata config)`:

1. Validates the facet address is non-zero and has deployed code
2. Validates the wires array is non-empty
3. If the integration ID already exists, deletes the old config and all its dispatch entries
4. For each wire, checks the call selector is not hardcoded and not already wired to another integration
5. Stores the config and creates dispatch entries
6. Emits `IntegrationSet(id, config)`

### Removing an Integration

`removeIntegration(bytes32 id)`:

1. Removes the integration ID from the enumerable set (reverts if not found)
2. Deletes the config and all its dispatch entries
3. Emits `IntegrationRemoved(id)`

### Syncing to a Controller

After the Beacon admin configures integrations, a Controller admin calls `controller.updateIntegrations(ids)`. The Controller fetches the configs from the Beacon via `IBeacon.getConfigs(ids)`, validates them again locally, and stores them in its own ERC-7201 storage. This two-step process (Beacon config, then Controller sync) means:

- The Beacon can be updated without immediately affecting any Controller
- Each Controller admin decides when to pull new configs
- Multiple Controllers can be at different config versions temporarily

### Stale integrations and `CallSelectorAlreadyWired`

Both the Beacon and the Controller keep a `callSelector → dispatch` map and refuse to wire the same incoming selector twice. On the Beacon, `_setConfigAndDispatches` requires `_dispatches[callSelector].facet == address(0)` before writing a wire, or it reverts with `CallSelectorAlreadyWired(callSelector)`. On the Controller, `updateIntegrations` applies the same rule against the Controller’s own `dispatches` storage.

The Beacon only enforces **global** non-collision among integrations that exist **on the Beacon at that moment**. When `removeIntegration` runs, the Beacon deletes that integration’s config and clears every dispatch slot its wires occupied, so those selectors become available for a different live integration.

The Controller does not automatically drop integrations when the Beacon removes them. Its `dispatches` entries are cleared only when an admin calls `removeIntegrations` for an ID, or when `updateIntegrations` **overwrites** an ID that is already installed (in which case it deletes that ID’s old wires before applying the new config from the Beacon). If an integration was removed from the Beacon but never removed from a given Controller, that Controller still holds the old wires and still occupies those call selectors locally.

That mismatch is how a sync can revert with `CallSelectorAlreadyWired`: a **new** integration on the Beacon may legally reuse a call selector that the Beacon has already freed, but the target Controller may still have that selector wired to a **stale** integration that is no longer in the Beacon. When `updateIntegrations` tries to install the new integration’s wires, `_setConfigAndDispatches` sees the selector already in use on the Controller and reverts—even though the Beacon’s own map has no collision for current integrations.

In short, the Beacon guarantees collision-free wiring among **current** Beacon integrations; it cannot guarantee that every Controller’s local copy is collision-free with **its** still-installed integrations until those admins run `removeIntegrations` (or otherwise reconcile IDs) before pulling configs that reuse selectors.

If a Controller admin wants to sync a new integration that is reusing a selector already wired by another unrelated integration, they should decide if they can safely remove or update the existing integration before syncing the new integration.

## Hardcoded Selector Protection

The Beacon prevents facets from overriding core function selectors that must remain available on every Controller. The `_revertIfCallSelectorIsHardcoded` function checks against:

**Controller admin/lifecycle selectors:**

- `updateIntegrations`
- `removeIntegrations`

**Controller getter selectors:**

- `accessControls`
- `beacon`
- `proxy`
- `rateLimits`

**Shared enumeration selectors (from IEnumerableIntegrations):**

- `integrations`
- `getConfig`
- `getConfigs`
- `getDispatch`
- `getDispatches`

If any wire's `callSelector` matches one of these, the Beacon reverts with `CallSelectorHardcoded(bytes4)`.

## Versioning: Beacon and Controller Must Stay in Sync

The Beacon and Controller share the same set of hardcoded protected selectors. If a new function is added to the Controller (e.g., a new admin function or getter), its selector must also be added to the Beacon's `_revertIfCallSelectorIsHardcoded` list. Otherwise, a Beacon admin could unknowingly wire an integration whose call selector collides with the new Controller function, causing that function to become unreachable on any Controller that syncs the integration.

This means Beacon and Controller upgrades are tightly coupled: any change to the Controller's explicit function signatures requires a corresponding Beacon update to protect those selectors.

## View Functions

| Function                    | Returns         | Description                                    |
| --------------------------- | --------------- | ---------------------------------------------- |
| `integrations()`            | `Integration[]` | All configured integrations with their configs |
| `getConfig(bytes32)`        | `Config`        | Config for a single integration ID             |
| `getConfigs(bytes32[])`     | `Config[]`      | Batch config fetch                             |
| `getDispatch(bytes4)`       | `Dispatch`      | Dispatch entry for a single call selector      |
| `getDispatches(bytes4[])`   | `Dispatch[]`    | Batch dispatch fetch                           |
| `supportsInterface(bytes4)` | `bool`          | ERC-165 support for `IBeacon`                  |
