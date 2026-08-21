# Advisory Review Automation

Claude review is a teammate workflow, not a facet gate. It posts findings, questions,
and suggestions while maintainers retain every policy and merge decision. Normal build,
test, repository coverage, and human-review requirements remain independent.

## Repository Setup

1. Configure `CLAUDE_CODE_OAUTH_TOKEN` as a repository or organization Actions secret
   with access to this repository. Rotate it under the normal secret-management policy.
2. Enable the repository setting that allows GitHub Actions to create pull requests; the
   reusable-guidance publisher needs it to open its human-reviewed proposal.
3. Give every Claude model job read-only repository and pull-request permissions. Fixed
   `github-script` publishers post automatic summaries, comment responses, and guidance
   proposals with separate least-privilege tokens.
4. Do not add the Claude review job to required branch-protection checks. Claude action
   failures, including exhausted turn budgets, remain visibly failed for diagnosis but
   do not block merging. Remove legacy `Facet Gate` statuses from branch protection
   while keeping ordinary CI checks.
5. Enable privileged review only for pull requests targeting the protected default
   branch. Automatic review uses `pull_request_target` so its workflow definition always
   comes from the protected default branch. It accepts fork submissions through the
   Claude action's non-write-user isolation, with read-only permissions and without
   executing pull-request-controlled code. Comment-triggered runs remain maintainer-only
   and must not execute pull-request-controlled code with base repository credentials.
6. Support maintainer `@claude` interactions through top-level pull-request comments.
   Resolve the target pull request first, reject closed or non-default-base pull requests,
   and run one structured read-only analysis from a protected default-branch checkout. A
   fixed publisher posts each response as a normal top-level comment. Inline review
   comments are intentionally excluded because their workflow ref is the pull-request
   merge. Load protected `REVIEW.md` and standards guidance rather than instructions
   supplied by the pull request.

For pull requests targeting the default branch, the non-blocking `review-context` job
resolves the current pull request and default-branch ref through GitHub's API, waits for
GitHub's synthetic test merge, and verifies that the merge commit's parents are the
current base tip and reported head. It then checks out that exact base SHA separately
from the validated synthetic PR merge, runs only the trusted base version of
`checks/review_context.py`, and uploads observations for the reviewed head. A stale event
or conflicted pull request is skipped before automatic review. Foundry is installed
before collection so `cast` is available to recompute ERC-7201 slots. The job has no
Claude or RPC secret and never executes a pull-request-supplied script. Automatic review
waits for this job but continues if context generation or artifact download is
unavailable after a merge is resolved. Context observations are untrusted review data,
not findings or verdicts.

There is a one-time rollout limitation for the pull request that first introduces the
collector: its base commit may not contain `checks/review_context.py`, so the trusted
base copy cannot run and automatic review proceeds without context. After that pull
request merges, normal later pull requests use the collector from their base commit.
Never execute the pull-request-authored collector as a fallback.

The first rollout of `pull_request_target` must itself land through a trusted
default-branch update. A pull request that changes its own trigger may receive no
automatic run because its proposed copy no longer subscribes to `pull_request` while the
default-branch copy does not yet subscribe to `pull_request_target`. Later pull requests
cannot replace the protected workflow definition with their proposed copy.

The automatic job is limited to non-draft pull requests targeting the default branch,
including fork submissions. The secret-bearing job definition comes from the protected
default branch, while the repository root contains guidance from the exact validated
base SHA (the pinned Claude action may restore protected files from the current base
branch).
The synthetic merge is isolated under `pr-merge/` with recursive dependencies. The job
never executes pull-request code and receives no RPC variables. Ordinary CI owns build,
test, and coverage execution; the review captures its current check state and may read
updated statuses and logs through read-only GitHub commands. Pending or unavailable CI
is reported as a limitation rather than rerun inside the secret-bearing Claude process.
Pull-request-authored Claude configuration is renamed and quarantined before the model
inspects the merge. Comment analysis likewise keeps a protected checkout, receives
read-only permissions, and never executes pull-request code. Fixed publishers revalidate
the pull request state, base branch, and head; automatic publication also revalidates the
exact reviewed base tip immediately before writing.

## Review Behavior

The workflow should follow `REVIEW.md` and
`standards/ADVERSARIAL_REVIEW.md`:

- classify points as findings, questions, or suggestions;
- support concrete claims with code paths and evidence;
- treat deterministic warnings as context, not conclusions;
- avoid duplicate comments and overall verdicts;
- post the public comment as a plain bullet list in a teammate's conversational voice,
  with unconfirmed leads in one collapsed block, and never mention rule IDs, severities,
  or the rulebook in public prose;
- keep the rule-by-rule technical reasoning in the structured `technical_analysis`
  output, which the workflow prints to its job logs and never publishes;
- write direct, concise, factual Plain English focused on behavior, impact, and evidence;
- use the soft, complexity-proportionate writing budgets in `REVIEW.md` without dropping
  material points or enforcing a technical length limit;
- read the full conversation before responding;
- retract or narrow a point when code evidence changes the conclusion; and
- treat ordinary authorized maintainer replies as feedback without requiring special
  learning syntax.

If the repository requires all conversations to be resolved, automatic findings should
use a top-level summary with file and line links rather than bot-created inline threads
that could indirectly block merge.

## Guidance Learning

Automatic review and every authorized maintainer comment use read-only structured model
analysis. Fixed publishers post the automatic summary and conversational responses after
checking that the reviewed head is still current; automatic summaries also require the
reviewed base tip to remain current. An explicit `@claude` request requires a response;
ordinary feedback receives one only when the evidence changes or usefully clarifies a
conclusion. Per-head and per-comment markers make reruns idempotent. A reusable lesson
may trigger a separate, narrowly permissioned path that:

1. verifies the discussion and current code;
2. creates or updates a dedicated guidance branch;
3. proposes a focused change only to `REVIEW.md`; and
4. opens a normal pull request for maintainer review.

Summary and response publishers have only pull-request write permission; the automatic
publisher additionally has read-only contents permission to revalidate the base tip. The
repository-writing publisher starts only when structured analysis explicitly marks a
complete `REVIEW.md` proposal as reusable. It verifies that default-branch guidance has
not changed since analysis, and each proposal uses a branch and marker derived from the
triggering comment. Never write learned guidance directly to the default branch. Do not
convert one-off exceptions into general policy without evidence that the reasoning is
reusable. Standards changes are ordinary human-authored pull requests and are outside
automated learning output.

## Operational Checks

After workflow changes are reviewed:

- confirm Claude's check is not required by branch protection;
- confirm normal build, test, and coverage checks remain required;
- inspect job permissions separately for automatic review, `@claude` interaction, and
  guidance proposals;
- confirm automatic and comment-triggered review reject pull requests whose base is not
  the protected default branch;
- confirm automatic review has no RPC environment or Forge command permissions and can
  read ordinary CI status;
- force a Claude action or turn-budget failure and confirm the non-required check fails
  visibly without blocking merge;
- test automatic review and ordinary maintainer replies on same-repository and fork branches;
- test that a pull request which changes `claude-review.yml` still runs the protected
  default-branch workflow definition and reviews the validated synthetic merge;
- test that stale events and conflicted pull requests do not start automatic review;
- test that a base-tip change before publication prevents the automatic comment;
- test that a fork receives an automatic review without executing pull-request code, and
  that non-maintainer `@claude` comments do not start comment analysis;
- test that an updated head may receive a new review, while a run with no new useful
  information avoids posting or posts only a brief status when needed;
- test that every direct `@claude` trigger receives one marker-keyed top-level response
  and invokes only the unified comment-analysis model path;
- submit two comments rapidly and confirm both independent comment-ID runs complete;
- test that unrelated maintainer feedback does not start the write-permission publisher;
- test that unavailable review context does not prevent automatic review;
- test a supported maintainer counterargument and confirm Claude acknowledges the
  changed conclusion; and
- test that reusable learning opens a comment-specific reviewable guidance PR rather
  than writing to the default branch or replacing another comment's proposal.

GitHub authentication, branch protection, workflow permissions, and event behavior must
be verified in the repository settings and Actions service; local documentation checks
cannot prove them.
