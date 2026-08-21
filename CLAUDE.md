# diamond-pau

Diamond-pattern PAU (Protocol Allocation Unit): a `Controller` delegatecalls immutable
facets that direct funds held by an `ALMProxy`, bounded by rate limits and role-based
access control. A facet executes with the Controller's storage context and full authority
over custody, so facet changes are a primary security boundary.

## Working On Facets

- Read `REVIEW.md` for collaborative review behavior.
- Read `standards/FACET_RULEBOOK.md` for the technical facet-submission rules,
  reviewer checks, and accepted reasoning.
- Read `standards/ADVERSARIAL_REVIEW.md` before reviewing or self-reviewing a facet.
- Prefer a focused design spec in `specs/<dir>.md` before implementing a new
  integration. Maintainers may accept contextual exceptions or follow-up documentation.
- Use the facet skills in `.claude/skills/` as authoring and review aids, not as merge
  authorities.
- Reference implementations: `src/facets/erc4626/` (stateful deposit/withdraw),
  `src/facets/transfer-asset/` (minimal), and `src/facets/wrap-proxy-eth/`
  (constructor/immutables). Reference tests: `test/mainnet-fork/Aave.t.sol`.

## Commands

- Build: `forge build --sizes ./src`
- Test: `FOUNDRY_PROFILE=ci forge test`
- Authority-path evidence (advisory): `python3 checks/check_forbidden.py`
- ERC-7201 slot evidence (advisory): `python3 checks/check_storage.py`
- Review automation tests:
  `python3 -m unittest checks/test_claude_workflow.py checks/test_advisory_scanners.py checks/test_review_context.py`

Both scanners are standalone review aids. They report leads for human interpretation,
return success even when they find evidence, and do not replace normal CI or review.

Fork tests require the applicable `MAINNET_RPC_URL`, `BASE_RPC_URL`, and
`AVALANCHE_RPC_URL` environment variables.

## Review Writing

Follow `REVIEW.md` for evidence, writing and response behavior, budgets, and output
shape.

## Security Context

- Facet code is Controller code because it runs through `delegatecall`.
- Treat `ALLOCATOR_ROLE` as compromisable.
- Route value movement through `ALMProxy.doCall` or `doCallWithValue`; facets never use
  `doDelegateCall`.
- Bound allocator-controlled outflows with correctly derived enforcing rate-limit keys
  and governance-controlled destinations.
- Recompute every ERC-7201 facet storage slot; never trust a copied constant.
- Read `docs/ARCHITECTURE.md`, `docs/THREAT_MODEL.md`, `docs/SECURITY.md`, and
  `docs/RATE_LIMITS.md` before changing protocol behavior or security assumptions.
