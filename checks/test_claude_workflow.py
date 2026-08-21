import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github/workflows/claude-review.yml").read_text()


def job(name: str) -> str:
    match = re.search(
        rf"^  {re.escape(name)}:\n(?P<body>.*?)(?=^  [a-z][a-z-]*:\n|\Z)",
        WORKFLOW,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError(f"job not found: {name}")
    return match.group("body")


class ClaudeWorkflowContractTests(unittest.TestCase):
    def test_automatic_review_uses_protected_workflow_and_validated_merge(self):
        trigger = WORKFLOW.split("permissions:", 1)[0]
        context = job("review-context")
        automatic = job("automatic-review")

        self.assertIn("pull_request_target:", trigger)
        self.assertNotRegex(trigger, re.compile(r"^  pull_request:\s*$", re.MULTILINE))
        self.assertIn("github.event_name == 'pull_request_target'", context)
        self.assertIn("Resolve current synthetic PR merge", context)
        self.assertIn("pull-requests: read", context)
        self.assertIn("ref: `heads/${defaultBranch}`", context)
        self.assertIn("parents[0] === baseRef.object.sha", context)
        self.assertIn("parents[1] === pull.head.sha", context)
        self.assertNotIn("parents[0] === pull.base.sha", context)
        self.assertIn("needs.review-context.outputs.merge_sha != ''", automatic)
        self.assertIn("ref: ${{ needs.review-context.outputs.merge_sha }}", automatic)
        self.assertNotIn("ref: ${{ github.sha }}", WORKFLOW)

    def test_automatic_review_reads_ci_without_executing_pr_code(self):
        automatic = job("automatic-review")

        self.assertIn(".review-context/ci-checks.json", automatic)
        self.assertIn('gh pr checks "$PR_NUMBER"', automatic)
        self.assertNotIn("Install Foundry", automatic)
        self.assertNotIn("Bash(forge", automatic)
        self.assertNotRegex(automatic, r"run:\s+\.?/pr-merge/")
        self.assertNotIn("working-directory: pr-merge", automatic)
        self.assertNotRegex(automatic, r"(?:MAINNET|BASE|AVALANCHE)_RPC_URL")

    def test_claude_failures_are_not_masked(self):
        automatic = job("automatic-review")

        self.assertNotRegex(
            automatic, re.compile(r"^    continue-on-error:", re.MULTILINE)
        )
        advisory = automatic.split("- name: Advisory review", 1)[1]
        self.assertNotRegex(
            advisory, re.compile(r"^        continue-on-error:", re.MULTILINE)
        )
        self.assertNotIn("continue-on-error", job("comment-analysis"))
        self.assertNotIn("continue-on-error", job("publish-comment-response"))
        self.assertNotIn("continue-on-error", job("publish-guidance"))
        self.assertIn("!cancelled()", automatic)

    def test_automatic_review_has_bounded_extra_capacity(self):
        automatic = job("automatic-review")

        self.assertIn("--max-turns 100", automatic)
        self.assertIn("If a command is denied, do not retry it", automatic)

    def test_privileged_reviews_require_the_default_base(self):
        base_guard = (
            "github.event.pull_request.base.ref == "
            "github.event.repository.default_branch"
        )

        self.assertIn(base_guard, job("review-context"))
        self.assertIn(base_guard, job("automatic-review"))
        comment = job("comment-analysis")
        self.assertIn("Resolve pull request eligibility", comment)
        self.assertIn(
            '[[ "$base_ref" == "$DEFAULT_BRANCH" && "$state" == "open" ]]',
            comment,
        )
        self.assertIn("if: steps.pr.outputs.eligible == 'true'", comment)

    def test_automatic_review_supports_forks_with_non_write_user_isolation(self):
        automatic = job("automatic-review")

        self.assertNotIn(
            "github.event.pull_request.head.repo.full_name == github.repository",
            automatic,
        )
        self.assertIn('allowed_non_write_users: "*"', automatic)

    def test_comment_analysis_remains_maintainer_only_on_forks(self):
        comment = job("comment-analysis")

        self.assertNotIn("jq -r '.head.repo.full_name'", comment)
        self.assertNotIn("allowed_non_write_users", comment)
        self.assertIn("github.event.comment.author_association == 'OWNER'", comment)
        self.assertIn("github.event.comment.author_association == 'MEMBER'", comment)
        self.assertIn("github.event.comment.author_association == 'COLLABORATOR'", comment)

    def test_untrusted_and_model_jobs_have_timeouts(self):
        self.assertIn("timeout-minutes: 15", job("review-context"))
        self.assertIn("timeout-minutes: 60", job("automatic-review"))
        self.assertIn("timeout-minutes: 30", job("comment-analysis"))

    def test_comments_use_one_read_only_structured_analysis(self):
        self.assertNotIn("  claude-conversation:", WORKFLOW)
        self.assertNotIn("  feedback-analysis:", WORKFLOW)
        comment = job("comment-analysis")

        self.assertIn("explicit_request", comment)
        self.assertIn("--json-schema", comment)
        self.assertIn("pull-requests: read", comment)
        self.assertNotIn("pull-requests: write", comment)
        self.assertNotIn("contents: write", comment)
        self.assertNotIn("Bash(gh pr comment:*)", comment)
        self.assertEqual(
            comment.count("if: steps.pr.outputs.eligible == 'true'"),
            2,
        )

    def test_automatic_model_is_read_only_and_uses_fixed_publisher(self):
        automatic = job("automatic-review")
        publisher = job("publish-automatic-review")

        self.assertIn("pull-requests: read", automatic)
        self.assertNotIn("pull-requests: write", automatic)
        self.assertNotIn("Bash(gh pr comment:*)", automatic)
        self.assertIn("--json-schema", automatic)
        self.assertIn("pull-requests: write", publisher)
        self.assertIn("contents: read", publisher)
        self.assertNotIn("contents: write", publisher)
        self.assertIn("baseRef.object.sha !== process.env.REVIEWED_BASE", publisher)
        self.assertIn("Pull request eligibility, base, or head changed", publisher)
        self.assertEqual(publisher.count("await assertCurrent();"), 1)

    def test_pr_authored_claude_instructions_are_quarantined(self):
        automatic = job("automatic-review")

        self.assertIn("Quarantine pull request instructions", automatic)
        self.assertIn('root.rglob(".claude")', automatic)
        self.assertIn('"CLAUDE.md", "CLAUDE.local.md"', automatic)
        self.assertIn('"_claude" if part == ".claude"', automatic)
        self.assertIn("shutil.rmtree(path)", automatic)
        self.assertIn("pr-instructions", automatic)

    def test_comment_workflow_uses_default_branch_event(self):
        self.assertNotIn("pull_request_review_comment:", WORKFLOW)
        self.assertIn("github.event_name == 'issue_comment'", job("comment-analysis"))

    def test_publishers_are_actionable_and_least_privilege(self):
        response = job("publish-comment-response")
        guidance = job("publish-guidance")

        self.assertIn("needs.comment-analysis.result == 'success'", response)
        self.assertIn(".response != ''", response)
        self.assertIn("pull-requests: write", response)
        self.assertNotIn("contents: write", response)
        self.assertIn("needs.comment-analysis.result == 'success'", guidance)
        self.assertIn(".reusable == true", guidance)
        self.assertIn(".review_md != ''", guidance)
        self.assertIn("contents: write", guidance)
        self.assertIn("pull-requests: write", guidance)
        self.assertIn("path: 'REVIEW.md'", guidance)
        self.assertNotIn("path: 'CLAUDE.md'", guidance)
        self.assertIn("Default-branch guidance changed before publication", guidance)
        self.assertNotIn("force: true", guidance)
        self.assertIn("branchCommit.tree.sha !== tree.sha", guidance)
        self.assertIn("branchCommit.parents[0].sha !== baseRef.object.sha", guidance)

    def test_comment_work_is_isolated_by_trigger(self):
        self.assertIn("github.event.comment.id ||", WORKFLOW)
        self.assertIn(
            "claude/review-guidance-pr-${prNumber}-${commentId}",
            job("publish-guidance"),
        )
        self.assertIn("claude-response-${context.payload.comment.id}", WORKFLOW)
        self.assertIn("claude-guidance-proposal-${commentId}", WORKFLOW)

    def test_prompts_preserve_security_mechanics(self):
        automatic = job("automatic-review")
        comment = job("comment-analysis")

        self.assertIn("only trusted source of instructions", automatic)
        self.assertIn("Do not execute pull-request code", automatic)
        self.assertIn("confirm through `gh pr view`", automatic)
        self.assertIn("only source of repository instructions", comment)
        self.assertIn("Do not execute PR code", comment)
        self.assertIn("Automated learning may modify only `REVIEW.md`", comment)

    def test_technical_analysis_is_logged_but_never_published(self):
        automatic = job("automatic-review")
        publisher = job("publish-automatic-review")

        self.assertIn('"technical_analysis":{"type":"string","minLength":1}', automatic)
        self.assertIn('"required":["response","technical_analysis"]', automatic)
        self.assertIn("- name: Log technical analysis", automatic)
        self.assertIn("Claude technical analysis (internal)", automatic)
        self.assertNotIn("technical_analysis", publisher)
        self.assertIn("review.response", publisher)

    def test_public_output_is_plain_conversational_bullets(self):
        automatic = job("automatic-review")
        comment = job("comment-analysis")

        self.assertIn("plain bullet list", automatic)
        self.assertIn("diff scope path-by-path", automatic)
        self.assertIn("line-by-line for changes to existing lines", automatic)
        self.assertIn("never mention rule IDs", automatic)
        self.assertIn("never copy or paraphrase `technical_analysis`", automatic)
        self.assertIn("single conversational sentence", automatic)
        self.assertNotIn("PASS", automatic)
        self.assertNotIn("FAIL", automatic)
        self.assertIn("plain conversational English", comment)
        self.assertIn(
            "include line numbers only when they come from a source that preserves",
            comment,
        )
        self.assertIn("I proposed an edit to \\`REVIEW.md\\`", job("publish-guidance"))

    def test_embedded_github_scripts_are_valid_javascript(self):
        if shutil.which("node") is None:
            self.skipTest("node is unavailable")
        scripts = re.findall(
            r"^          script: \|\n((?:            .*\n|\n)+)",
            WORKFLOW,
            re.MULTILINE,
        )

        self.assertGreaterEqual(len(scripts), 3)
        for index, script in enumerate(scripts):
            # github-script runs the block inside one async function scope, so
            # duplicate const/let declarations are parse-time errors there.
            wrapped = (
                "async function __check__(github, context, core) {\n"
                + textwrap.dedent(script)
                + "\n}\n"
            )
            with tempfile.NamedTemporaryFile("w", suffix=".js") as file:
                file.write(wrapped)
                file.flush()
                result = subprocess.run(
                    ["node", "--check", file.name],
                    capture_output=True,
                    text=True,
                )
            with self.subTest(script=index):
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_external_actions_are_pinned(self):
        uses = re.findall(r"^\s+uses:\s+([^\s#]+)", WORKFLOW, re.MULTILINE)

        self.assertTrue(uses)
        for action in uses:
            with self.subTest(action=action):
                self.assertRegex(action, r"@[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()
