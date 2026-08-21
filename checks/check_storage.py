#!/usr/bin/env python3
"""Advisory ERC-7201 slot recomputation and collision scan."""

import argparse
import re
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = REPO_ROOT / "src"
NAMESPACE_RE = re.compile(r"@custom:storage-location\s+erc7201:([\w.-]+)")
SLOT_RE = re.compile(r"\b\w*STORAGE_LOCATION\w*\s*=\s*(0x[0-9a-fA-F]{64})")

# SharedControllerStorage is the canonical owner of its slot. The reentrancy slot is
# defined by OpenZeppelin outside src/, so any declaration in the scanned tree matters.
RESERVED_SLOTS = {
    "0x77adf60bdbfedf206f8b8310f3d364080b7f61dcc0e46caac13c29bb1eb5cc00": (
        "SharedControllerStorage",
        "src/ControllerSharedStorage.sol",
    ),
    "0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00": (
        "OpenZeppelin ReentrancyGuard",
        None,
    ),
}


@dataclass(frozen=True)
class Declaration:
    path: str
    line: int
    namespace: str | None
    slot: str


def keccak(data: str | bytes) -> str:
    argument = data if isinstance(data, str) else "0x" + data.hex()
    result = subprocess.run(
        ["cast", "keccak", argument], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise SystemExit(f"cast keccak failed: {result.stderr.strip()}")
    return result.stdout.strip()


def erc7201_slot(namespace: str) -> str:
    first_hash = int(keccak(namespace), 16)
    second_hash = int(keccak((first_hash - 1).to_bytes(32, "big")), 16)
    return f"0x{second_hash & ~0xff:064x}"


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


def strip_comments(source: str) -> str:
    """Blank comments while preserving newlines and source offsets."""

    def blank(match: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", match.group(0))

    return re.sub(r"//[^\n]*|/\*.*?\*/", blank, source, flags=re.S)


def associate_storage_locations(
    source: str,
) -> tuple[
    list[tuple[re.Match[str], re.Match[str] | None]],
    list[re.Match[str]],
    list[re.Match[str]],
]:
    """Associate each namespace with only the next constant before another namespace."""
    namespaces = list(NAMESPACE_RE.finditer(source))
    slots = list(SLOT_RE.finditer(strip_comments(source)))
    events = sorted(
        [(match.start(), "namespace", match) for match in namespaces]
        + [(match.start(), "slot", match) for match in slots]
    )
    associated = []
    unpaired_namespaces = []
    unpaired_constants = []
    pending_namespace = None
    for _, kind, match in events:
        if kind == "namespace":
            if pending_namespace is not None:
                unpaired_namespaces.append(pending_namespace)
            pending_namespace = match
            continue
        associated.append((match, pending_namespace))
        if pending_namespace is None:
            unpaired_constants.append(match)
        pending_namespace = None
    if pending_namespace is not None:
        unpaired_namespaces.append(pending_namespace)
    return associated, unpaired_namespaces, unpaired_constants


def declarations(path: Path) -> tuple[list[Declaration], list[str], list[str]]:
    source = path.read_text()
    associated, namespace_matches, constant_matches = associate_storage_locations(source)
    shown_path = display_path(path)

    def line(match: re.Match[str]) -> int:
        return source.count("\n", 0, match.start()) + 1

    declarations = []
    for slot_match, namespace_match in associated:
        declarations.append(
            Declaration(
                path=shown_path,
                line=line(slot_match),
                namespace=(
                    namespace_match.group(1) if namespace_match is not None else None
                ),
                slot=slot_match.group(1).lower(),
            )
        )

    unpaired_namespaces = [
        f"{shown_path}:{line(match)}: namespace "
        f"{match.group(1)} has no paired storage-location constant"
        for match in namespace_matches
    ]
    unpaired_constants = [
        f"{shown_path}:{line(match)}: storage-location "
        f"constant {match.group(1).lower()} has no paired ERC-7201 namespace"
        for match in constant_matches
    ]
    return declarations, unpaired_namespaces, unpaired_constants


def analyze(paths: list[Path]) -> tuple[int, list[str]]:
    all_declarations = []
    evidence = []
    for path in solidity_files(paths):
        found, unpaired_namespaces, unpaired_constants = declarations(path)
        all_declarations.extend(found)
        evidence.extend(unpaired_namespaces)
        evidence.extend(unpaired_constants)

    owners = defaultdict(list)
    for declaration in all_declarations:
        owners[declaration.slot].append(declaration)
        if declaration.namespace is not None:
            computed = erc7201_slot(declaration.namespace).lower()
            if computed != declaration.slot:
                evidence.append(
                    f"{declaration.path}:{declaration.line}: declared {declaration.slot}, "
                    f"computed {computed} from {declaration.namespace}"
                )

        reserved = RESERVED_SLOTS.get(declaration.slot)
        if reserved and declaration.path != reserved[1]:
            evidence.append(
                f"{declaration.path}:{declaration.line}: {declaration.slot} collides "
                f"with reserved {reserved[0]} storage"
            )

    for slot, declarations_for_slot in sorted(owners.items()):
        by_path = defaultdict(list)
        for declaration in declarations_for_slot:
            by_path[declaration.path].append(declaration)
        for path, file_declarations in sorted(by_path.items()):
            if len(file_declarations) < 2:
                continue
            locations = ", ".join(
                f"{declaration.path}:{declaration.line} "
                f"({declaration.namespace or 'no paired namespace'})"
                for declaration in sorted(
                    file_declarations,
                    key=lambda item: (item.path, item.line, item.namespace or ""),
                )
            )
            evidence.append(
                f"{slot} is declared multiple times in {path}: {locations}"
            )
        if len(by_path) > 1:
            locations = ", ".join(
                f"{declaration.path}:{declaration.line} "
                f"({declaration.namespace or 'no paired namespace'})"
                for declaration in sorted(
                    declarations_for_slot,
                    key=lambda item: (item.path, item.line, item.namespace or ""),
                )
            )
            evidence.append(
                f"{slot} is declared multiple times across files: {locations}"
            )

    return len(all_declarations), evidence


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Solidity files or directories (default: src)",
    )
    args = parser.parse_args()

    declaration_count, evidence = analyze(args.paths or [DEFAULT_ROOT])

    if evidence:
        print("Advisory ERC-7201 storage evidence:")
        for item in evidence:
            print(f"  {item}")
        print(
            "Review this evidence in context; this advisory scan does not produce a verdict."
        )
    else:
        print(
            f"Advisory ERC-7201 scan: recomputed {declaration_count} declaration(s); "
            "no mismatches or collisions found."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
