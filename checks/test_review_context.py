import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# Support direct execution as well as root-level unittest discovery.
REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from checks import check_storage, review_context


SLOT = "0x" + "11" * 32
MISMATCH_SLOT = "0x" + "22" * 32
COMPUTED_SLOT = "0x" + "33" * 32
RESERVED_SLOT = next(iter(check_storage.RESERVED_SLOTS))
CONSTANT_ONLY_SLOT = "0x" + "44" * 32
SOURCE_ORDER_SLOT = "0x" + "55" * 32
LATER_SLOT = "0x" + "66" * 32
LEADING_SLOT = "0x" + "77" * 32


def declaration(namespace: str, slot: str) -> str:
    return (
        f"/// @custom:storage-location erc7201:{namespace}\n"
        f"bytes32 internal constant FACET_STORAGE_LOCATION = {slot};\n"
    )


def constant(slot: str, name: str = "FACET_STORAGE_LOCATION") -> str:
    return f"bytes32 internal constant {name} = {slot};\n"


class TemporaryRepo:
    def __init__(self, root: Path):
        self.root = root
        self.git("init", "-q")
        self.git("config", "user.email", "review-context@example.com")
        self.git("config", "user.name", "Review Context Test")

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", *args], cwd=self.root, capture_output=True, text=True, check=True
        )
        return result.stdout.strip()

    def write(self, path: str, content: str) -> None:
        destination = self.root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content)

    def commit(self, message: str) -> str:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")


class ReviewContextTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = TemporaryRepo(Path(self.temporary.name))

        self.repo.write("docs/OLD_NAME.md", "rename evidence\n" * 20)
        self.repo.write("docs/THREAT_MODEL.md", "surface A\n")
        self.repo.write(
            "test/mainnet-fork/ForkTestBase.t.sol",
            "address[27] internal facets;\n",
        )
        self.repo.write("test/unit/FacetVersions.t.sol", "contract FacetVersions {}\n")
        self.repo.write("src/Controller.sol", "contract Controller {}\n")
        self.repo.write("src/facets/risky/TypeChanged.sol", "contract TypeChanged {}\n")
        self.repo.write("foundry.toml", "[profile.default]\n")
        self.repo.write("README.md", "base\n")
        self.repo.write("deleted.txt", "one\ntwo\nthree\n")
        self.base = self.repo.commit("base")

        (self.repo.root / "docs/OLD_NAME.md").rename(self.repo.root / "docs/NEW_NAME.md")
        self.repo.write("docs/THREAT_MODEL.md", "surface A\nsurface B\n")
        self.repo.write(
            "test/mainnet-fork/ForkTestBase.t.sol",
            "address[28] internal facets;\n",
        )
        self.repo.write("src/Controller.sol", "contract Controller { uint256 value; }\n")
        self.repo.write("foundry.toml", "[profile.default]\nsolc = '0.8.34'\n")
        self.repo.write("lib/example/README.md", "dependency root\n")
        self.repo.write("checks/example.txt", "review automation\n")
        self.repo.write("README.md", "head\n")
        (self.repo.root / "deleted.txt").unlink()
        (self.repo.root / "src/facets/risky/TypeChanged.sol").unlink()
        binary = self.repo.root / "binary.dat"
        binary.write_bytes(b"\x00\x01review context\n")

        risky = (
            "interface IAccessControl {\n"
            "    function grantRole(bytes32 role, address user) external;\n"
            "}\n"
            "contract RiskyFacet {\n"
            "    // grantRole(role, user);\n"
            "    function run() external {\n"
            "        proxy.doDelegateCall(target, data);\n"
            "        target.delegatecall(data);\n"
            "        grantRole(role, user);\n"
            "        acl.grantRole(role, user);\n"
            "        selfdestruct(payable(user));\n"
            "    }\n"
            "}\n"
            + declaration("sky.pau.storage.RiskyFacet.v1", MISMATCH_SLOT)
        )
        self.repo.write("src/facets/risky/RiskyFacet.sol", risky)
        self.repo.write("src/facets/risky/IRiskyFacet.sol", "interface IRiskyFacet {}\n")
        self.repo.write(
            "src/facets/risky/Duplicate.sol",
            declaration("sky.pau.storage.First.v1", SLOT)
            + declaration("sky.pau.storage.Second.v1", SLOT),
        )
        self.repo.write(
            "src/facets/risky/CrossFile.sol",
            declaration("sky.pau.storage.Third.v1", SLOT),
        )
        self.repo.write(
            "src/facets/risky/Reserved.sol",
            declaration("sky.pau.storage.Reserved.v1", RESERVED_SLOT),
        )
        self.repo.write(
            "src/facets/risky/ConstantOnlyDuplicate.sol",
            constant(CONSTANT_ONLY_SLOT, "FIRST_STORAGE_LOCATION")
            + constant(CONSTANT_ONLY_SLOT, "SECOND_STORAGE_LOCATION"),
        )
        self.repo.write(
            "src/facets/risky/ConstantOnlyCross.sol",
            constant(CONSTANT_ONLY_SLOT),
        )
        self.repo.write(
            "src/facets/risky/ConstantOnlyReserved.sol",
            constant(RESERVED_SLOT),
        )
        self.repo.write(
            "src/facets/risky/NamespaceOnly.sol",
            "/// @custom:storage-location erc7201:sky.pau.storage.NamespaceOnly.v1\n",
        )
        (self.repo.root / "src/facets/risky/SymlinkFacet.sol").symlink_to(
            "RiskyFacet.sol"
        )
        (self.repo.root / "src/facets/risky/TypeChanged.sol").symlink_to(
            "RiskyFacet.sol"
        )
        self.repo.write(
            "specs/risky.md",
            "---\nfacet: RiskyFacet\ndir: risky\nchains: [mainnet]\n"
            "integration_doc: RISKY_INTEGRATION.md\ndependencies: []\n---\n",
        )
        self.repo.write("docs/RISKY_INTEGRATION.md", "integration\n")
        self.repo.write(
            "test/unit/rate-limits/RateLimitHelpers.t.sol",
            "contract RateLimitHelpersTest {}\n",
        )
        self.repo.write("test/mainnet-fork/Risky.t.sol", "contract RiskyForkTest {}\n")
        self.repo.write(
            "test/integration/facets/RiskyFacet.t.sol",
            "contract RiskyIntegrationTest {}\n",
        )
        self.repo.git("add", "-A")
        self.repo.git(
            "update-index",
            "--add",
            "--cacheinfo",
            "160000",
            self.base,
            "vendor/example-gitlink",
        )
        self.repo.git("commit", "-q", "-m", "head")
        self.head = self.repo.git("rev-parse", "HEAD")

    def compute_slot(self, namespace: str) -> str:
        if namespace == "sky.pau.storage.RiskyFacet.v1":
            return COMPUTED_SLOT
        if namespace == "sky.pau.storage.Reserved.v1":
            return RESERVED_SLOT
        if namespace == "sky.pau.storage.FirstSourceOrder.v1":
            return SOURCE_ORDER_SLOT
        if namespace == "sky.pau.storage.LaterSourceOrder.v1":
            return LATER_SLOT
        return SLOT

    def collect(self):
        with mock.patch.object(review_context, "cast_is_usable", return_value=True):
            with mock.patch.object(
                review_context.check_storage,
                "erc7201_slot",
                side_effect=self.compute_slot,
            ):
                return review_context.collect_context(
                    self.repo.root, self.base, self.head, self.head
                )

    def test_categories_rename_dependencies_and_shared_array_rewrite(self):
        context = self.collect()
        changes = {item["path"]: item for item in context["changed_files"]}

        self.assertEqual(changes["src/facets/risky/RiskyFacet.sol"]["categories"], ["facet"])
        self.assertEqual(changes["src/Controller.sol"]["categories"], ["core"])
        self.assertEqual(changes["specs/risky.md"]["categories"], ["spec"])
        self.assertEqual(changes["docs/THREAT_MODEL.md"]["categories"], ["shared", "docs"])
        self.assertEqual(
            changes["test/mainnet-fork/ForkTestBase.t.sol"]["categories"],
            ["shared", "test"],
        )
        self.assertEqual(changes["lib/example/README.md"]["categories"], ["dependency"])
        self.assertEqual(changes["checks/example.txt"]["categories"], ["review_automation"])
        self.assertEqual(changes["README.md"]["categories"], ["other"])
        self.assertEqual(changes["docs/NEW_NAME.md"]["status"], "R")
        self.assertEqual(changes["docs/NEW_NAME.md"]["old_path"], "docs/OLD_NAME.md")
        self.assertEqual(context["dependencies"]["changed_roots"], ["example"])
        self.assertTrue(context["dependencies"]["foundry_toml_changed"])
        self.assertEqual(changes["deleted.txt"]["status"], "D")
        self.assertEqual(changes["deleted.txt"]["additions"], 0)
        self.assertEqual(changes["deleted.txt"]["deletions"], 3)
        self.assertTrue(changes["binary.dat"]["binary"])
        self.assertEqual(changes["src/facets/risky/TypeChanged.sol"]["status"], "T")

        shared = {
            item["path"]: item for item in context["shared_file_hunks"]
        }["test/mainnet-fork/ForkTestBase.t.sol"]
        lines = [line for hunk in shared["hunks"] for line in hunk["lines"]]
        self.assertIn(
            {"kind": "deletion", "old_line": 1, "new_line": None, "text": "address[27] internal facets;"},
            lines,
        )
        self.assertIn(
            {"kind": "addition", "old_line": None, "new_line": 1, "text": "address[28] internal facets;"},
            lines,
        )

    def test_diff_scope_evidence_groups_paths_and_counts_shared_lines(self):
        evidence = self.collect()["diff_scope_evidence"]

        self.assertTrue(evidence["applicable"])
        self.assertEqual(evidence["touched_facet_dirs"], ["risky"])
        self.assertEqual(evidence["facet_names"], ["Risky"])
        for path in (
            "src/facets/risky/RiskyFacet.sol",
            "test/mainnet-fork/Risky.t.sol",
            "test/integration/facets/RiskyFacet.t.sol",
            "docs/RISKY_INTEGRATION.md",
        ):
            self.assertIn(path, evidence["facet_owned_paths"])

        shared = {item["path"]: item for item in evidence["shared_paths"]}
        fork_base = shared["test/mainnet-fork/ForkTestBase.t.sol"]
        self.assertEqual(fork_base["addition_lines"], 1)
        self.assertEqual(fork_base["deletion_lines"], 1)
        self.assertFalse(fork_base["additions_only"])
        threat_model = shared["docs/THREAT_MODEL.md"]
        self.assertEqual(threat_model["deletion_lines"], 0)
        self.assertTrue(threat_model["additions_only"])
        helper_tests = shared["test/unit/rate-limits/RateLimitHelpers.t.sol"]
        self.assertTrue(helper_tests["additions_only"])

        self.assertIn("lib/example/README.md", evidence["dependency_paths"])
        for path in (
            "README.md",
            "src/Controller.sol",
            "specs/risky.md",
            "checks/example.txt",
            "docs/NEW_NAME.md",
            "docs/OLD_NAME.md",
        ):
            self.assertIn(path, evidence["unmatched_paths"])
        self.assertNotIn(
            "test/integration/facets/RiskyFacet.t.sol", evidence["unmatched_paths"]
        )

    def test_facet_paths_are_explicit_observations(self):
        facet = self.collect()["facets"][0]

        self.assertEqual(facet["directory"], "risky")
        self.assertTrue(facet["implementation"]["exists_as_regular_file"])
        self.assertEqual(facet["implementation"]["status"], "A")
        self.assertTrue(facet["interface"]["changed"])
        self.assertTrue(facet["spec"]["exists_as_regular_file"])
        self.assertTrue(facet["integration_doc"]["exists_as_regular_file"])
        self.assertTrue(facet["integration_test"]["exists_as_regular_file"])
        fork_paths = {item["path"]: item for item in facet["fork_tests"]}
        self.assertTrue(fork_paths["test/mainnet-fork/Risky.t.sol"]["exists_as_regular_file"])
        absent = fork_paths["test/base-fork/Risky.t.sol"]
        self.assertFalse(absent["exists_as_regular_file"])
        self.assertTrue(facet["unit_version_test"]["exists_as_regular_file"])
        self.assertFalse(facet["unit_version_test"]["changed"])

    def test_tree_revision_controls_content_without_hiding_changed_facet_paths(self):
        with mock.patch.object(review_context, "cast_is_usable", return_value=False):
            context = review_context.collect_context(
                self.repo.root, self.base, self.head, self.base
            )

        facet = context["facets"][0]
        self.assertEqual(context["identifiers"]["review_tree"], self.repo.git("rev-parse", f"{self.base}^{{tree}}"))
        self.assertEqual(facet["name"], "Risky")
        self.assertFalse(facet["implementation"]["exists_as_regular_file"])
        self.assertTrue(facet["implementation"]["changed"])
        self.assertEqual(facet["implementation"]["status"], "A")

    def test_review_tree_can_contain_content_independent_of_head(self):
        self.repo.write("test/base-fork/Risky.t.sol", "contract SyntheticMergeTest {}\n")
        self.repo.git("add", "test/base-fork/Risky.t.sol")
        review_tree = self.repo.git("write-tree")
        with mock.patch.object(review_context, "cast_is_usable", return_value=False):
            context = review_context.collect_context(
                self.repo.root, self.base, self.head, review_tree
            )

        fork_test = next(
            item
            for item in context["facets"][0]["fork_tests"]
            if item["path"] == "test/base-fork/Risky.t.sol"
        )
        self.assertEqual(context["identifiers"]["review_tree"], review_tree)
        self.assertTrue(fork_test["exists_as_regular_file"])
        self.assertFalse(fork_test["changed"])

    def test_diff_scope_uses_merge_base_when_event_base_has_diverged(self):
        self.repo.git("checkout", "-q", "-b", "event-base", self.base)
        self.repo.write("event-base-only.txt", "not part of the head-side diff\n")
        event_base = self.repo.commit("divergent event base")
        with mock.patch.object(review_context, "cast_is_usable", return_value=False):
            context = review_context.collect_context(
                self.repo.root, event_base, self.head, self.head
            )

        self.assertEqual(context["identifiers"]["base"], event_base)
        self.assertEqual(context["identifiers"]["merge_base"], self.base)
        self.assertEqual(
            context["identifiers"]["diff_scope"], f"{self.base}..{self.head}"
        )
        self.assertNotIn(
            "event-base-only.txt", {item["path"] for item in context["changed_files"]}
        )

    def test_non_regular_tree_entries_are_not_read_as_source(self):
        repo = review_context.GitRepo(self.repo.root)
        entries = repo.tree_entries(repo.resolve_tree(self.head))
        symlink = entries["src/facets/risky/SymlinkFacet.sol"]
        gitlink = entries["vendor/example-gitlink"]

        self.assertEqual((symlink["mode"], symlink["type"]), ("120000", "blob"))
        self.assertIsNone(repo.read_regular_blob(entries, "src/facets/risky/SymlinkFacet.sol"))
        self.assertEqual((gitlink["mode"], gitlink["type"]), ("160000", "commit"))
        self.assertIsNone(repo.read_regular_blob(entries, "vendor/example-gitlink"))
        for kind, mode in (("tree", "040000"),):
            synthetic = {"Unsafe.sol": {"mode": mode, "type": kind, "object": "unused"}}
            self.assertIsNone(repo.read_regular_blob(synthetic, "Unsafe.sol"))
            self.assertFalse(
                review_context.path_observation("Unsafe.sol", synthetic, {})[
                    "exists_as_regular_file"
                ]
            )

    def test_authority_patterns_are_narrow_and_comments_are_ignored(self):
        observations = self.collect()["authority_evidence"]["observations"]

        self.assertEqual(len(observations), 5)
        self.assertEqual([item["line"] for item in observations], [7, 8, 9, 10, 11])
        self.assertEqual(
            {item["pattern"] for item in observations},
            {description for _, description in review_context.check_forbidden.PATTERNS},
        )

    def test_storage_source_order_pairing_and_collision_evidence(self):
        source = (
            constant(LEADING_SLOT, "LEADING_STORAGE_LOCATION")
            + "/// @custom:storage-location erc7201:sky.pau.storage.Orphan.v1\n"
            + "/// @custom:storage-location erc7201:sky.pau.storage.FirstSourceOrder.v1\n"
            + constant(SOURCE_ORDER_SLOT, "FIRST_STORAGE_LOCATION")
            + constant(SOURCE_ORDER_SLOT, "EXTRA_STORAGE_LOCATION")
            + "/// @custom:storage-location erc7201:sky.pau.storage.LaterSourceOrder.v1\n"
            + constant(LATER_SLOT, "LATER_STORAGE_LOCATION")
        )
        path = "src/facets/risky/SourceOrder.sol"
        self.repo.write(path, source)
        source_order_head = self.repo.commit("source-order storage")
        with mock.patch.object(review_context, "cast_is_usable", return_value=True):
            with mock.patch.object(
                review_context.check_storage,
                "erc7201_slot",
                side_effect=self.compute_slot,
            ):
                storage = review_context.collect_context(
                    self.repo.root, self.base, source_order_head, source_order_head
                )["storage_evidence"]

        declarations = [item for item in storage["declarations"] if item["path"] == path]
        self.assertEqual(
            [item["namespace"] for item in declarations],
            [
                None,
                "sky.pau.storage.FirstSourceOrder.v1",
                None,
                "sky.pau.storage.LaterSourceOrder.v1",
            ],
        )
        self.assertEqual([item["line"] for item in declarations], [1, 4, 5, 7])
        namespaces = [item for item in storage["unpaired_namespaces"] if item["path"] == path]
        self.assertEqual(
            namespaces,
            [{"path": path, "line": 2, "namespace": "sky.pau.storage.Orphan.v1"}],
        )
        constants = [item for item in storage["unpaired_constants"] if item["path"] == path]
        self.assertEqual([item["line"] for item in constants], [1, 5])
        collision = next(
            item for item in storage["same_file_collisions"] if item["path"] == path
        )
        self.assertEqual(collision["slot"], SOURCE_ORDER_SLOT)
        self.assertEqual([item["line"] for item in collision["declarations"]], [4, 5])

    def test_storage_mismatch_reserved_and_both_collision_scopes(self):
        storage = self.collect()["storage_evidence"]

        self.assertTrue(storage["cast_available"])
        self.assertEqual(len(storage["mismatches"]), 1)
        self.assertEqual(storage["mismatches"][0]["declared_slot"], MISMATCH_SLOT)
        self.assertEqual(storage["mismatches"][0]["computed_slot"], COMPUTED_SLOT)
        reserved_paths = {item["path"] for item in storage["reserved_collisions"]}
        self.assertEqual(
            reserved_paths,
            {
                "src/facets/risky/ConstantOnlyReserved.sol",
                "src/facets/risky/Reserved.sol",
            },
        )
        same_file = {item["path"]: item for item in storage["same_file_collisions"]}
        self.assertIn("src/facets/risky/Duplicate.sol", same_file)
        self.assertIn("src/facets/risky/ConstantOnlyDuplicate.sol", same_file)
        cross_file = {item["slot"]: item for item in storage["cross_file_collisions"]}
        self.assertEqual(
            cross_file[SLOT]["paths"],
            ["src/facets/risky/CrossFile.sol", "src/facets/risky/Duplicate.sol"],
        )
        self.assertEqual(
            cross_file[CONSTANT_ONLY_SLOT]["paths"],
            [
                "src/facets/risky/ConstantOnlyCross.sol",
                "src/facets/risky/ConstantOnlyDuplicate.sol",
            ],
        )
        self.assertEqual(
            storage["unpaired_namespaces"],
            [
                {
                    "path": "src/facets/risky/NamespaceOnly.sol",
                    "line": 1,
                    "namespace": "sky.pau.storage.NamespaceOnly.v1",
                }
            ],
        )
        self.assertEqual(len(storage["unpaired_constants"]), 4)
        constant_only = [item for item in storage["declarations"] if item["namespace"] is None]
        self.assertEqual(len(constant_only), 4)
        self.assertTrue(all(item["computed_slot"] is None for item in constant_only))

    def test_output_is_deterministic_observational_and_exit_zero(self):
        first = self.repo.root / "first.json"
        second = self.repo.root / "second.json"
        argv = [
            "--repo",
            str(self.repo.root),
            "--base",
            self.base,
            "--head",
            self.head,
            "--tree",
            self.head,
        ]
        with mock.patch.object(review_context, "cast_is_usable", return_value=True):
            with mock.patch.object(
                review_context.check_storage,
                "erc7201_slot",
                side_effect=self.compute_slot,
            ):
                self.assertEqual(review_context.main([*argv, "--output", str(first)]), 0)
                self.assertEqual(review_context.main([*argv, "--output", str(second)]), 0)

        self.assertEqual(first.read_bytes(), second.read_bytes())
        context = json.loads(first.read_text())
        self.assertNotIn("interpretation", context)
        execution = context["execution_evidence"]
        self.assertFalse(execution["collector_ran_build"])
        self.assertFalse(execution["collector_ran_tests"])
        self.assertFalse(execution["collector_ran_coverage"])
        self.assertFalse(execution["build_result_available"])
        self.assertFalse(execution["test_result_available"])
        self.assertFalse(execution["coverage_result_available"])

        vocabulary = []
        pending = [context]
        while pending:
            value = pending.pop()
            if isinstance(value, dict):
                vocabulary.extend(str(key).lower() for key in value)
                pending.extend(value.values())
            elif isinstance(value, list):
                pending.extend(value)
            elif isinstance(value, str):
                vocabulary.append(value.lower())
        rendered_vocabulary = "\n".join(vocabulary)
        for term in (
            "policy",
            "verdict",
            "decision",
            "interpretation",
            "requirement",
            "instruction",
            "should",
            "severity",
            "rule",
            "violation",
            "pass",
            "fail",
            "compliance",
            "claude should",
        ):
            self.assertNotIn(term, rendered_vocabulary)

    def test_cast_limitation_still_collects_storage_and_exits_zero(self):
        output = self.repo.root / "without-cast.json"
        with mock.patch.object(review_context, "cast_is_usable", return_value=False):
            result = review_context.main(
                [
                    "--repo",
                    str(self.repo.root),
                    "--base",
                    self.base,
                    "--head",
                    self.head,
                    "--output",
                    str(output),
                ]
            )

        self.assertEqual(result, 0)
        storage = json.loads(output.read_text())["storage_evidence"]
        self.assertFalse(storage["cast_available"])
        self.assertIsNotNone(storage["limitation"])
        self.assertGreater(storage["declaration_count"], 0)
        self.assertEqual(len(storage["reserved_collisions"]), 2)


if __name__ == "__main__":
    unittest.main()
