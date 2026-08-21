#!/usr/bin/env python3
"""Collect deterministic, observational context for a code review."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

try:
    from checks import check_forbidden, check_storage
except ModuleNotFoundError:  # Direct execution: python3 checks/review_context.py
    import check_forbidden
    import check_storage


CATEGORY_ORDER = (
    "facet",
    "shared",
    "core",
    "spec",
    "docs",
    "test",
    "dependency",
    "review_automation",
    "other",
)
FACET_BASE_FILES = {"src/facets/Facet.sol", "src/facets/IFacet.sol"}
SHARED_FILES = {
    *FACET_BASE_FILES,
    "test/unit/FacetVersions.t.sol",
    "test/mainnet-fork/ForkTestBase.t.sol",
    "test/base-fork/ForkTestBase.t.sol",
    "test/avalanche-fork/ForkTestBase.t.sol",
    "test/integration/TestBase.t.sol",
    "test/interfaces/IMainnetControllerFull.sol",
    "test/interfaces/IForeignControllerFull.sol",
    "test/mainnet-fork/Attacks.t.sol",
    "docs/THREAT_MODEL.md",
    "src/libraries/RateLimitHelpers.sol",
    "test/unit/rate-limits/RateLimitHelpers.t.sol",
}
FORK_DIRS = ("mainnet-fork", "base-fork", "avalanche-fork")
HUNK_RE = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?$"
)


class ContextError(Exception):
    pass


class GitRepo:
    def __init__(self, path: Path):
        self.path = path.expanduser().resolve()
        if not self.path.is_dir():
            raise ContextError(f"repository is not a directory: {self.path}")
        result = self.run("rev-parse", "--is-inside-work-tree", check=False)
        if result.returncode != 0 or result.stdout.strip() != b"true":
            raise ContextError(f"not a usable Git work tree: {self.path}")

    def run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
        try:
            result = subprocess.run(
                ["git", *args],
                cwd=self.path,
                capture_output=True,
                check=False,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ContextError(f"unable to run Git command: {' '.join(args)}") from error
        if check and result.returncode != 0:
            detail = result.stderr.decode("utf-8", "replace").strip()
            raise ContextError(detail or f"Git command failed: {' '.join(args)}")
        return result

    def resolve_commit(self, revision: str) -> str:
        result = self.run(
            "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"
        )
        return result.stdout.decode().strip()

    def resolve_tree(self, revision: str) -> str:
        result = self.run(
            "rev-parse", "--verify", "--end-of-options", f"{revision}^{{tree}}"
        )
        return result.stdout.decode().strip()

    def tree_entries(self, tree: str) -> dict[str, dict[str, str]]:
        output = self.run("ls-tree", "-r", "-z", "--full-tree", tree).stdout
        entries = {}
        for record in output.split(b"\0"):
            if not record:
                continue
            metadata, raw_path = record.split(b"\t", 1)
            mode, kind, object_id = metadata.decode().split(" ")
            path = raw_path.decode("utf-8", "surrogateescape")
            entries[path] = {"mode": mode, "type": kind, "object": object_id}
        return entries

    def read_regular_blob(
        self, entries: dict[str, dict[str, str]], path: str
    ) -> str | None:
        entry = entries.get(path)
        if not entry or entry["type"] != "blob" or not entry["mode"].startswith("100"):
            return None
        data = self.run("cat-file", "blob", entry["object"]).stdout
        return data.decode("utf-8", "replace")


def categories_for(path: str, old_path: str | None = None) -> list[str]:
    categories = set()
    for candidate in (path, old_path):
        if not candidate:
            continue
        if candidate.startswith("src/facets/") and candidate not in FACET_BASE_FILES:
            categories.add("facet")
        if candidate in SHARED_FILES:
            categories.add("shared")
        if candidate.startswith("src/") and not (
            candidate.startswith("src/facets/") and candidate not in FACET_BASE_FILES
        ):
            categories.add("core")
        if candidate.startswith("specs/"):
            categories.add("spec")
        if candidate.startswith("docs/"):
            categories.add("docs")
        if candidate.startswith("test/"):
            categories.add("test")
        if candidate in {".gitmodules", "foundry.toml", "foundry.lock"} or candidate.startswith(
            "lib/"
        ):
            categories.add("dependency")
        if candidate.startswith("checks/") or candidate.startswith(".github/workflows/"):
            categories.add("review_automation")
    if not categories:
        categories.add("other")
    return [category for category in CATEGORY_ORDER if category in categories]


def parse_name_status(output: bytes) -> list[dict]:
    tokens = output.split(b"\0")
    changes = []
    index = 0
    while index < len(tokens) and tokens[index]:
        detail = tokens[index].decode()
        index += 1
        old_path = None
        if detail[0] in {"R", "C"}:
            old_path = tokens[index].decode("utf-8", "surrogateescape")
            path = tokens[index + 1].decode("utf-8", "surrogateescape")
            index += 2
        else:
            path = tokens[index].decode("utf-8", "surrogateescape")
            index += 1
        change = {"path": path, "status": detail[0], "status_detail": detail}
        if old_path is not None:
            change["old_path"] = old_path
        if detail[0] in {"R", "C"} and detail[1:].isdigit():
            change["similarity_percent"] = int(detail[1:])
        changes.append(change)
    return changes


def parse_numstat(output: bytes) -> dict[str, tuple[int | None, int | None]]:
    tokens = output.split(b"\0")
    stats = {}
    index = 0
    while index < len(tokens) and tokens[index]:
        added_raw, deleted_raw, raw_path = tokens[index].split(b"\t", 2)
        index += 1
        if raw_path:
            path = raw_path.decode("utf-8", "surrogateescape")
        else:
            index += 1  # old path for a rename/copy
            path = tokens[index].decode("utf-8", "surrogateescape")
            index += 1
        added = None if added_raw == b"-" else int(added_raw)
        deleted = None if deleted_raw == b"-" else int(deleted_raw)
        stats[path] = (added, deleted)
    return stats


def changed_files(repo: GitRepo, merge_base: str, head: str) -> list[dict]:
    diff_args = ("--find-renames", merge_base, head)
    changes = parse_name_status(
        repo.run("diff", "--name-status", "-z", *diff_args).stdout
    )
    stats = parse_numstat(repo.run("diff", "--numstat", "-z", *diff_args).stdout)
    for change in changes:
        added, deleted = stats.get(change["path"], (None, None))
        change["additions"] = added
        change["deletions"] = deleted
        change["binary"] = added is None or deleted is None
        change["categories"] = categories_for(change["path"], change.get("old_path"))
    return sorted(changes, key=lambda item: (item["path"], item.get("old_path", "")))


def parse_hunks(diff: str) -> tuple[list[dict], bool]:
    hunks = []
    current = None
    old_line = new_line = 0
    binary = False
    for raw_line in diff.splitlines():
        match = HUNK_RE.match(raw_line)
        if match:
            old_line = int(match.group(1))
            new_line = int(match.group(3))
            current = {
                "old_start": old_line,
                "old_count": int(match.group(2) or 1),
                "new_start": new_line,
                "new_count": int(match.group(4) or 1),
                "lines": [],
            }
            hunks.append(current)
            continue
        if raw_line.startswith("Binary files ") or raw_line == "GIT binary patch":
            binary = True
        if current is None:
            continue
        if raw_line == "\\ No newline at end of file":
            if current["lines"]:
                current["lines"][-1]["no_newline_at_end"] = True
            continue
        prefix = raw_line[:1]
        if prefix not in {" ", "+", "-"}:
            continue
        line = {
            "kind": {" ": "context", "+": "addition", "-": "deletion"}[prefix],
            "old_line": old_line if prefix != "+" else None,
            "new_line": new_line if prefix != "-" else None,
            "text": raw_line[1:],
        }
        current["lines"].append(line)
        if prefix != "+":
            old_line += 1
        if prefix != "-":
            new_line += 1
    return hunks, binary


def shared_hunks(
    repo: GitRepo, merge_base: str, head: str, changes: list[dict]
) -> list[dict]:
    observations = []
    for change in changes:
        if "shared" not in change["categories"]:
            continue
        paths = [change.get("old_path"), change["path"]]
        output = repo.run(
            "diff",
            "--unified=3",
            "--no-color",
            "--no-ext-diff",
            "--no-textconv",
            "--find-renames",
            merge_base,
            head,
            "--",
            *(path for path in paths if path),
        ).stdout.decode("utf-8", "replace")
        hunks, binary = parse_hunks(output)
        item = {"path": change["path"], "hunks": hunks, "binary": binary}
        if "old_path" in change:
            item["old_path"] = change["old_path"]
        observations.append(item)
    return observations


def diff_scope_evidence(
    changes: list[dict],
    shared_observations: list[dict],
    review_entries: dict[str, dict[str, str]],
    merge_entries: dict[str, dict[str, str]],
) -> dict:
    facet_dirs = touched_facet_dirs(changes)
    names = set()
    for directory in facet_dirs:
        name = (
            facet_name_from_tree(review_entries, directory)
            or facet_name_from_tree(merge_entries, directory)
            or facet_name_from_changes(changes, directory)
        )
        if name:
            names.add(name)

    def facet_owned(path: str) -> bool:
        for directory in facet_dirs:
            if path.startswith(f"src/facets/{directory}/"):
                return True
        for name in names:
            escaped = re.escape(name)
            if re.fullmatch(rf"test/mainnet-fork/{escaped}[^/]*\.t\.sol", path):
                return True
            if path in (
                f"test/base-fork/{name}.t.sol",
                f"test/avalanche-fork/{name}.t.sol",
            ):
                return True
            if path == f"test/integration/facets/{name}Facet.t.sol":
                return True
            if re.fullmatch(rf"test/unit/{escaped}[^/]*\.t\.sol", path):
                return True
            if path == f"docs/{name.upper()}_INTEGRATION.md":
                return True
        return False

    line_counts = {}
    for item in shared_observations:
        additions = deletions = 0
        for hunk in item["hunks"]:
            for line in hunk["lines"]:
                if line["kind"] == "addition":
                    additions += 1
                elif line["kind"] == "deletion":
                    deletions += 1
        line_counts[item["path"]] = {
            "addition_lines": additions,
            "deletion_lines": deletions,
            "binary": item["binary"],
            "additions_only": not item["binary"] and deletions == 0,
        }

    facet_owned_paths = set()
    shared_paths = {}
    dependency_paths = set()
    unmatched_paths = set()
    for change in changes:
        for path in (change["path"], change.get("old_path")):
            if not path:
                continue
            if path in SHARED_FILES:
                entry = {"path": path}
                entry.update(
                    line_counts.get(
                        path,
                        {
                            "addition_lines": None,
                            "deletion_lines": None,
                            "binary": None,
                            "additions_only": None,
                        },
                    )
                )
                shared_paths[path] = entry
            elif facet_owned(path):
                facet_owned_paths.add(path)
            elif path in {".gitmodules", "foundry.toml", "foundry.lock"} or path.startswith(
                "lib/"
            ):
                dependency_paths.add(path)
            else:
                unmatched_paths.add(path)
    return {
        "scope": (
            "changed paths grouped by the facet-submission path conventions; "
            "groupings are observational"
        ),
        "applicable": bool(facet_dirs),
        "touched_facet_dirs": facet_dirs,
        "facet_names": sorted(names),
        "facet_owned_paths": sorted(facet_owned_paths),
        "shared_paths": [shared_paths[path] for path in sorted(shared_paths)],
        "dependency_paths": sorted(dependency_paths),
        "unmatched_paths": sorted(unmatched_paths),
    }


def parse_frontmatter(text: str | None) -> dict[str, str | list[str]]:
    if not text or not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    values = {}
    for line in parts[1].splitlines():
        match = re.match(r"^([\w-]+):\s*(.*)$", line.strip())
        if not match:
            continue
        key, value = match.groups()
        if value.startswith("[") and value.endswith("]"):
            values[key] = [
                item.strip().strip("\"'")
                for item in value[1:-1].split(",")
                if item.strip()
            ]
        else:
            values[key] = value.strip().strip("\"'")
    return values


def path_observation(
    path: str,
    entries: dict[str, dict[str, str]],
    changes_by_path: dict[str, tuple[dict, str]],
) -> dict:
    entry = entries.get(path)
    regular = bool(entry and entry["type"] == "blob" and entry["mode"].startswith("100"))
    matched_change = changes_by_path.get(path)
    change = matched_change[0] if matched_change else None
    return {
        "path": path,
        "exists_as_regular_file": regular,
        "changed": change is not None,
        "status": change["status"] if change else None,
        "change_path_role": matched_change[1] if matched_change else None,
    }


def touched_facet_dirs(changes: list[dict]) -> list[str]:
    directories = set()
    for change in changes:
        for path in (change["path"], change.get("old_path")):
            if not path or path in FACET_BASE_FILES:
                continue
            match = re.match(r"^src/facets/([^/]+)/", path)
            if match:
                directories.add(match.group(1))
    return sorted(directories)


def facet_name_from_tree(entries: dict[str, dict[str, str]], directory: str) -> str | None:
    prefix = f"src/facets/{directory}/"
    names = []
    for path, entry in entries.items():
        name = path.removeprefix(prefix)
        if (
            path.startswith(prefix)
            and "/" not in name
            and name.endswith("Facet.sol")
            and not name.startswith("I")
            and entry["type"] == "blob"
            and entry["mode"].startswith("100")
        ):
            names.append(name[: -len("Facet.sol")])
    return sorted(names)[0] if names else None


def facet_name_from_changes(changes: list[dict], directory: str) -> str | None:
    prefix = f"src/facets/{directory}/"
    names = []
    for change in changes:
        for path in (change["path"], change.get("old_path")):
            if not path or not path.startswith(prefix):
                continue
            name = path.removeprefix(prefix)
            if "/" not in name and name.endswith("Facet.sol") and not name.startswith("I"):
                names.append(name[: -len("Facet.sol")])
    return sorted(names)[0] if names else None


def facet_observations(
    repo: GitRepo,
    review_entries: dict[str, dict[str, str]],
    merge_entries: dict[str, dict[str, str]],
    changes: list[dict],
) -> list[dict]:
    changes_by_path = {}
    for change in changes:
        changes_by_path[change["path"]] = (change, "current")
        if "old_path" in change:
            changes_by_path[change["old_path"]] = (change, "previous")
    observations = []
    for directory in touched_facet_dirs(changes):
        spec_path = f"specs/{directory}.md"
        spec_text = repo.read_regular_blob(review_entries, spec_path)
        metadata = parse_frontmatter(spec_text)
        name = facet_name_from_tree(review_entries, directory)
        if name is None:
            name = facet_name_from_tree(merge_entries, directory)
        if name is None:
            name = facet_name_from_changes(changes, directory)
        facet_value = metadata.get("facet")
        if name is None and isinstance(facet_value, str) and facet_value.endswith("Facet"):
            name = facet_value[: -len("Facet")]

        item = {"directory": directory, "name": name}
        if name is None:
            item["observation"] = "no conventional implementation name was derived"
            item["implementation"] = None
            item["interface"] = None
            item["integration_doc"] = None
            item["fork_tests"] = []
            item["integration_test"] = None
        else:
            item["observation"] = "paths derived from repository names and spec metadata"
            item["implementation"] = path_observation(
                f"src/facets/{directory}/{name}Facet.sol", review_entries, changes_by_path
            )
            item["interface"] = path_observation(
                f"src/facets/{directory}/I{name}Facet.sol", review_entries, changes_by_path
            )
            doc_name = metadata.get("integration_doc")
            if not isinstance(doc_name, str) or not doc_name:
                doc_name = f"{name.upper()}_INTEGRATION.md"
            item["integration_doc"] = path_observation(
                f"docs/{doc_name}", review_entries, changes_by_path
            )
            item["fork_tests"] = [
                path_observation(
                    f"test/{fork_dir}/{name}.t.sol", review_entries, changes_by_path
                )
                for fork_dir in FORK_DIRS
            ]
            item["integration_test"] = path_observation(
                f"test/integration/facets/{name}Facet.t.sol",
                review_entries,
                changes_by_path,
            )
        item["spec"] = path_observation(spec_path, review_entries, changes_by_path)
        chains = metadata.get("chains", [])
        item["spec_chains"] = chains if isinstance(chains, list) else []
        item["unit_version_test"] = path_observation(
            "test/unit/FacetVersions.t.sol", review_entries, changes_by_path
        )
        observations.append(item)
    return observations


def authority_evidence(
    repo: GitRepo,
    entries: dict[str, dict[str, str]],
    facet_dirs: list[str],
) -> dict:
    evidence = []
    prefixes = tuple(f"src/facets/{directory}/" for directory in facet_dirs)
    for path in sorted(entries):
        if not prefixes or not path.startswith(prefixes) or not path.endswith(".sol"):
            continue
        source = repo.read_regular_blob(entries, path)
        if source is None:
            continue
        for line, description in check_forbidden.scan_source(source):
            evidence.append(
                {
                    "path": path,
                    "line": line,
                    "pattern": description,
                }
            )
    return {
        "scope": "regular Solidity files in touched facet directories at the review tree",
        "patterns": [description for _, description in check_forbidden.PATTERNS],
        "comment_stripping": True,
        "observations": sorted(
            evidence, key=lambda item: (item["path"], item["line"], item["pattern"])
        ),
    }


def cast_is_usable(repo_path: Path) -> bool:
    executable = shutil.which("cast")
    if executable is None:
        return False
    try:
        Path(executable).resolve().relative_to(repo_path)
    except ValueError:
        return True
    return False


def storage_evidence(
    repo: GitRepo,
    entries: dict[str, dict[str, str]],
) -> dict:
    declarations = []
    unpaired_namespaces = []
    unpaired_constants = []
    for path in sorted(entries):
        if not path.startswith("src/") or not path.endswith(".sol"):
            continue
        source = repo.read_regular_blob(entries, path)
        if source is None:
            continue
        associated, namespace_matches, constant_matches = (
            check_storage.associate_storage_locations(source)
        )
        for match in namespace_matches:
            unpaired_namespaces.append(
                {
                    "path": path,
                    "line": source.count("\n", 0, match.start()) + 1,
                    "namespace": match.group(1),
                }
            )
        for match in constant_matches:
            unpaired_constants.append(
                {
                    "path": path,
                    "line": source.count("\n", 0, match.start()) + 1,
                    "declared_slot": match.group(1).lower(),
                }
            )
        for slot_match, namespace_match in associated:
            declarations.append(
                {
                    "path": path,
                    "line": source.count("\n", 0, slot_match.start()) + 1,
                    "namespace": (
                        namespace_match.group(1)
                        if namespace_match is not None
                        else None
                    ),
                    "declared_slot": slot_match.group(1).lower(),
                    "computed_slot": None,
                    "matches_recomputed": None,
                }
            )

    cast_usable = cast_is_usable(repo.path)
    limitation = None
    if not cast_usable:
        limitation = "cast is unavailable outside the repository; slots were not recomputed"
    else:
        try:
            for declaration in declarations:
                if declaration["namespace"] is None:
                    continue
                computed = check_storage.erc7201_slot(declaration["namespace"]).lower()
                declaration["computed_slot"] = computed
                declaration["matches_recomputed"] = computed == declaration["declared_slot"]
        except (FileNotFoundError, OSError, SystemExit, ValueError):
            cast_usable = False
            limitation = "cast could not recompute ERC-7201 slots"
            for declaration in declarations:
                declaration["computed_slot"] = None
                declaration["matches_recomputed"] = None

    mismatches = [
        declaration.copy()
        for declaration in declarations
        if declaration["matches_recomputed"] is False
    ]
    reserved_collisions = []
    owners = defaultdict(list)
    for declaration in declarations:
        owners[declaration["declared_slot"]].append(declaration)
        reserved = check_storage.RESERVED_SLOTS.get(declaration["declared_slot"])
        if reserved and declaration["path"] != reserved[1]:
            reserved_collisions.append(
                {
                    "path": declaration["path"],
                    "line": declaration["line"],
                    "slot": declaration["declared_slot"],
                    "reserved_owner": reserved[0],
                }
            )

    same_file = []
    cross_file = []
    for slot, slot_declarations in sorted(owners.items()):
        by_path = defaultdict(list)
        for declaration in slot_declarations:
            by_path[declaration["path"]].append(declaration)
        for path, file_declarations in sorted(by_path.items()):
            if len(file_declarations) > 1:
                same_file.append(
                    {"slot": slot, "path": path, "declarations": file_declarations}
                )
        if len(by_path) > 1:
            cross_file.append(
                {
                    "slot": slot,
                    "paths": sorted(by_path),
                    "declarations": sorted(
                        slot_declarations,
                        key=lambda item: (
                            item["path"],
                            item["line"],
                            item["namespace"] or "",
                        ),
                    ),
                }
            )

    return {
        "scope": "regular Solidity files under src at the review tree",
        "cast_available": cast_usable,
        "limitation": limitation,
        "declaration_count": len(declarations),
        "declarations": declarations,
        "unpaired_namespaces": unpaired_namespaces,
        "unpaired_constants": unpaired_constants,
        "mismatches": mismatches,
        "reserved_collisions": reserved_collisions,
        "same_file_collisions": same_file,
        "cross_file_collisions": cross_file,
    }


def dependency_evidence(changes: list[dict]) -> dict:
    paths = set()
    for change in changes:
        paths.add(change["path"])
        if "old_path" in change:
            paths.add(change["old_path"])
    roots = sorted(
        {
            path.split("/", 2)[1]
            for path in paths
            if path.startswith("lib/") and len(path.split("/", 2)) > 1
        }
    )
    return {
        "changed_roots": roots,
        "gitmodules_changed": ".gitmodules" in paths,
        "foundry_toml_changed": "foundry.toml" in paths,
        "foundry_lock_changed": "foundry.lock" in paths,
    }


def collect_context(repo_path: Path, base: str, head: str, tree: str | None) -> dict:
    repo = GitRepo(repo_path)
    base_commit = repo.resolve_commit(base)
    head_commit = repo.resolve_commit(head)
    merge_base = repo.run("merge-base", base_commit, head_commit).stdout.decode().strip()
    if not merge_base:
        raise ContextError("base and head have no merge base")
    review_revision = tree or head
    review_tree = repo.resolve_tree(review_revision)
    review_entries = repo.tree_entries(review_tree)
    merge_tree = repo.resolve_tree(merge_base)
    merge_entries = repo.tree_entries(merge_tree)
    changes = changed_files(repo, merge_base, head_commit)
    facet_dirs = touched_facet_dirs(changes)
    shared_observations = shared_hunks(repo, merge_base, head_commit, changes)

    return {
        "schema_version": 1,
        "identifiers": {
            "base": base_commit,
            "head": head_commit,
            "merge_base": merge_base,
            "review_tree": review_tree,
            "requested_base": base,
            "requested_head": head,
            "requested_tree": review_revision,
            "diff_scope": f"{merge_base}..{head_commit}",
            "scope_derivation": "three-dot merge-base to head",
        },
        "changed_files": changes,
        "shared_file_hunks": shared_observations,
        "diff_scope_evidence": diff_scope_evidence(
            changes, shared_observations, review_entries, merge_entries
        ),
        "facets": facet_observations(repo, review_entries, merge_entries, changes),
        "dependencies": dependency_evidence(changes),
        "authority_evidence": authority_evidence(repo, review_entries, facet_dirs),
        "storage_evidence": storage_evidence(repo, review_entries),
        "execution_evidence": {
            "source": "review context collector",
            "collector_ran_build": False,
            "collector_ran_tests": False,
            "collector_ran_coverage": False,
            "build_result_available": False,
            "test_result_available": False,
            "coverage_result_available": False,
        },
    }


def write_json(path: Path, context: dict) -> None:
    destination = path.expanduser()
    parent = destination.parent
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=parent, prefix=f".{destination.name}.", delete=False
        ) as output:
            temporary = Path(output.name)
            json.dump(context, output, indent=2, ensure_ascii=True)
            output.write("\n")
        os.replace(temporary, destination)
    except OSError as error:
        if "temporary" in locals():
            temporary.unlink(missing_ok=True)
        raise ContextError(f"unable to write output: {destination}") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--tree")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        context = collect_context(args.repo, args.base, args.head, args.tree)
        write_json(args.output, context)
    except ContextError as error:
        print(f"review_context: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
