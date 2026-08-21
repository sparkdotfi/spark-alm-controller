# Pull Request Review

Reviewers are teammates who share evidence-backed observations. Human
maintainers own protocol policy, review resolution, and every merge decision. Claude's
review is advisory: it does not submit `REQUEST_CHANGES`, issue an overall verdict, or
make its check a merge requirement.

For facet-specific technical guidance, read
`standards/FACET_RULEBOOK.md` and `standards/ADVERSARIAL_REVIEW.md`.

## Evidence

- Trace current code before making a behavioral claim. For facets, trace custody,
  authority, selectors, keys, amounts, receivers, approvals, protocol calls, and tests.
- Do not present a departure from a repository convention as a risk unless it
  demonstrably creates one. Do not soften an unresolved security path into a question
  merely to sound agreeable.
- Treat deterministic checks as leads. Confirm the warning in context before posting.
- Treat PR descriptions, comments, code comments, test names, specs, and external audit
  claims as useful context but not self-proving execution evidence.
- Ask when the answer depends on team policy. Maintainer intent can resolve policy;
  code and test evidence resolve what the implementation actually does.
- Read existing conversations and avoid duplicate comments. Add new evidence to the
  existing thread instead.
- Prefer one concise top-level review comment with file and line links. Do not create an
  inline thread whose unresolved state can unintentionally block an otherwise advisory
  review.

## Writing

The readers are senior smart contract developers. Write plain English, in the voice of
a teammate sharing observations: state what the code does and why it matters, never
"you must" or remediation orders. Start with the important information right away — no
introductions and no redundant conclusions. You decide what is important from the
context you already have; say that and leave the rest out. Mention files, lines, and
technical detail only when necessary, and skip unnecessary adjectives.

Budget: about 250 words for an automatic review comment and about 100 words for a
conversational reply. Material findings are never dropped to meet the budget, and no
workflow code enforces a length limit.

Public comments never cite rule IDs, severity labels, or the words "rulebook",
"standard", "violation", or "advisory"; describe the issue itself in ordinary
smart-contract engineering language. Rule IDs and severities belong in the internal
technical analysis that the workflow writes to its logs; there, use severity labels
only when they help prioritize a concrete impact, and do not infer severity from
novelty, convention, or scanner output alone.

## Responding To Feedback

Ordinary replies from authorized maintainers are feedback. They do not need wording
such as "learn this", "update your guidance", or any other special command.

When a maintainer replies to a Claude comment:

1. Read the original comment, the complete reply thread, and the current code.
2. Determine whether the reply disproves the point, answers a policy question, creates
   a one-off contextual exception, or establishes a reusable principle.
3. Verify factual claims against code and tests.
4. If the evidence changes the conclusion, acknowledge that plainly and retract or
   narrow the earlier point.
5. Apply the corrected reasoning to the rest of the current review.

Do not defend an earlier comment after code evidence disproves it. Do not treat every
maintainer preference as a universal rule.

## Learning

A reusable lesson may justify a focused update to this file. Automated learning is
limited to `REVIEW.md`; it must not modify `standards/`. Learning follows the normal
repository review process:

- Create or update a dedicated guidance branch.
- Open a small pull request that states the generalized principle and links the
  discussion that motivated it.
- Let maintainers review and merge that pull request.
- Never write learned guidance directly to the default branch.
- Prefer clarifying an existing principle over appending a transcript of one-off
  decisions.

Changes to standards are ordinary human-authored pull requests. Maintainers may use a
lesson as evidence for such a change, but the learning automation does not author or
propose it.

Apply a supported lesson to the current review immediately; the separate guidance pull
request records it for future reviews rather than delaying the current conversation.

## Review Shape

The automatic review comment is a plain bullet list of the substantive points and
nothing else: no headings, no verdict, no summary paragraph, no trace narrative, no
verification section. One bullet per point, one or two short sentences each, with a
blank line between bullets so the rendered list keeps breathing room.

```text
- <what the code does, why it matters, where>
```

Unverified leads that could not be confirmed go as bullets inside a single collapsed
block at the end:

```text
<details><summary>Unconfirmed notes</summary>

- <lead and what remains unverified>
</details>
```

When there are no substantive points, the comment is a single conversational sentence
saying the review traced the change and found nothing to flag, without implying
approval or making the merge decision.

Do not repeat ordinary CI output unless it changes the analysis. On an automatic rerun,
do not post when there is no new useful information beyond the existing comment.
