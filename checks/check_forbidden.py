#!/usr/bin/env python3
"""Advisory scan for explicit authority-escalation paths in facet source."""

import argparse
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = REPO_ROOT / "src" / "facets"

# These patterns identify direct execution or ACL mutation primitives. Broader style,
# structure, test-shape, and policy conventions intentionally do not belong here.
ACL_MUTATION_RE = r"\b(?:grantRole|revokeRole|renounceRole|setRoleAdmin)\s*\("
PATTERNS = (
    (r"\.doDelegateCall\s*\(", "ALMProxy doDelegateCall path"),
    (r"\.delegatecall\s*\(", "raw delegatecall path"),
    (ACL_MUTATION_RE, "access-control mutation path"),
    (r"\bselfdestruct\s*\(", "selfdestruct path"),
)


def strip_comments(source: str) -> str:
    """Blank comments while preserving newlines and source offsets."""

    def blank(match: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", match.group(0))

    return re.sub(r"//[^\n]*|/\*.*?\*/", blank, source, flags=re.S)


def solidity_files(paths: list[Path]):
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.sol"))
        elif path.suffix == ".sol":
            yield path


def display_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def scan_source(source: str) -> list[tuple[int, str]]:
    source = strip_comments(source)
    findings = []
    for pattern, description in PATTERNS:
        for match in re.finditer(pattern, source):
            if pattern == ACL_MUTATION_RE and re.search(
                r"\bfunction\s*$", source[: match.start()], flags=re.S
            ):
                continue
            findings.append((source.count("\n", 0, match.start()) + 1, description))
    return sorted(findings)


def scan(path: Path) -> list[tuple[int, str]]:
    return scan_source(path.read_text())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Solidity files or directories (default: src/facets)",
    )
    args = parser.parse_args()

    findings = []
    for path in solidity_files(args.paths or [DEFAULT_ROOT]):
        findings.extend(
            (display_path(path), line, description)
            for line, description in scan(path)
        )

    if findings:
        print("Advisory authority-path evidence:")
        for path, line, description in findings:
            print(f"  {path}:{line}: {description}")
        print(
            "Review this evidence in context; this advisory scan does not produce a verdict."
        )
    else:
        print("Advisory authority scan: no explicit forbidden paths found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
