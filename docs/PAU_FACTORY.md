# PAU Factory

This document describes the `PAUFactory` contract, the deployment contract for creating DiamondPAU system instances.

## Purpose

PAUFactory serves one role: **atomic deployment** of complete PAU systems (ALMProxy, RateLimits, AccessControls, Controller) via a single `deploy()` call. The factory takes a Beacon address at construction and passes it to every Controller it deploys, so all Controllers share the same integration configuration source.

> **Note:** Controllers deployed as upgrades to live systems are not required to use the factory. The factory exists purely for convenience when spinning up entirely new PAU deployments.

## Relationship to Beacon

The factory does not manage integration configs or facet validation. That responsibility belongs entirely to the Beacon. The factory simply wires each new Controller to the shared Beacon so that the admin can later call `controller.updateIntegrations()` to sync configs from it.

## Deployment

`deploy(address admin)` atomically creates and configures a full PAU system:

1. Create ALMProxy and RateLimits with the factory as initial admin.
2. Create AccessControls with the passed `admin`.
3. Create Controller with references to AccessControls, Beacon, ALMProxy, and RateLimits.
4. Grant `CONTROLLER` role to the Controller on both ALMProxy and RateLimits.
5. Grant `DEFAULT_ADMIN_ROLE` to the passed `admin` on ALMProxy and RateLimits.
6. Revoke the factory's own `DEFAULT_ADMIN_ROLE` on ALMProxy and RateLimits, so the factory cannot control deployed systems after setup.
7. Emit `PAUDeployed` event with all deployed addresses.

## Security Considerations

- **Factory self-revokes after deployment.** The factory revokes its own admin roles on ALMProxy and RateLimits at the end of `deploy()`, preventing the factory from controlling deployed systems.

- **Beacon is immutable on the factory.** The Beacon address is set at construction and cannot be changed. All Controllers deployed by a given factory will reference the same Beacon.
