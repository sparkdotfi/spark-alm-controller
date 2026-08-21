import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# Support both discovery from checks/ and the documented root-level module command.
CHECKS_DIR = Path(__file__).resolve().parent
if str(CHECKS_DIR) not in sys.path:
    sys.path.insert(0, str(CHECKS_DIR))

import check_forbidden
import check_storage


SLOT = "0x" + "11" * 32
OTHER_SLOT = "0x" + "22" * 32
CONSTANT_ONLY_SLOT = "0x" + "44" * 32
LEADING_SLOT = "0x" + "55" * 32
LATER_SLOT = "0x" + "66" * 32


def storage_declaration(namespace: str, slot: str = SLOT) -> str:
    return (
        f"/// @custom:storage-location erc7201:{namespace}\n"
        f"bytes32 internal constant FACET_STORAGE_LOCATION = {slot};\n"
    )


def storage_constant(slot: str, name: str = "FACET_STORAGE_LOCATION") -> str:
    return f"bytes32 internal constant {name} = {slot};\n"


class ForbiddenScannerTests(unittest.TestCase):
    def test_comment_stripping_preserves_lines_and_hides_patterns(self):
        source = "// proxy.doDelegateCall(target, data);\n/* acl.grantRole(role, user); */\n"
        stripped = check_forbidden.strip_comments(source)

        self.assertEqual(stripped.count("\n"), source.count("\n"))
        self.assertNotIn("doDelegateCall", stripped)
        self.assertNotIn("grantRole", stripped)

    def test_scan_reports_direct_authority_paths(self):
        source = """contract Unsafe {
    function run() external {
        proxy.doDelegateCall(target, data);
        target.delegatecall(data);
        acl.grantRole(role, user);
        selfdestruct(payable(user));
    }
}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Unsafe.sol"
            path.write_text(source)

            descriptions = [description for _, description in check_forbidden.scan(path)]

        self.assertEqual(
            descriptions,
            [
                "ALMProxy doDelegateCall path",
                "raw delegatecall path",
                "access-control mutation path",
                "selfdestruct path",
            ],
        )

    def test_scan_reports_inherited_acl_calls_but_not_comments_or_declarations(self):
        source = """interface IAccessControl {
    function grantRole(bytes32 role, address user) external;
    function revokeRole(bytes32 role, address user) external;
    function renounceRole(bytes32 role, address user) external;
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}
contract InheritedAcl is IAccessControl {
    function run() external {
        // grantRole(role, user);
        grantRole(role, user);
        acl.revokeRole(role, user);
        renounceRole(role, user);
        setRoleAdmin(role, adminRole);
    }
}
"""
        findings = check_forbidden.scan_source(source)

        self.assertEqual([line for line, _ in findings], [10, 11, 12, 13])
        self.assertTrue(
            all(description == "access-control mutation path" for _, description in findings)
        )

    def test_findings_are_advisory_and_exit_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Unsafe.sol"
            path.write_text("contract Unsafe { function f() external { x.delegatecall(d); } }")
            output = io.StringIO()
            with mock.patch.object(sys, "argv", ["check_forbidden.py", str(path)]):
                with contextlib.redirect_stdout(output):
                    result = check_forbidden.main()

        self.assertEqual(result, 0)
        self.assertIn("raw delegatecall path", output.getvalue())
        self.assertIn("does not produce a verdict", output.getvalue())


class StorageScannerTests(unittest.TestCase):
    def analyze(self, files: dict[str, str], computed_slot: str = SLOT):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in files.items():
                (root / name).write_text(source)
            with mock.patch.object(check_storage, "erc7201_slot", return_value=computed_slot):
                return check_storage.analyze([root])

    def test_comment_stripping_ignores_commented_slot_constants(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Comments.sol"
            path.write_text(
                "/// @custom:storage-location erc7201:sky.pau.storage.Comments.v1\n"
                f"// bytes32 constant OLD_STORAGE_LOCATION = {SLOT};\n"
            )

            declarations, unpaired_namespaces, unpaired_constants = (
                check_storage.declarations(path)
            )

        self.assertEqual(declarations, [])
        self.assertEqual(len(unpaired_namespaces), 1)
        self.assertIn("has no paired storage-location constant", unpaired_namespaces[0])
        self.assertEqual(unpaired_constants, [])

    def test_unpaired_constants_are_indexed_for_same_and_cross_file_collisions(self):
        count, evidence = self.analyze(
            {
                "First.sol": storage_constant(CONSTANT_ONLY_SLOT, "FIRST_STORAGE_LOCATION")
                + storage_constant(CONSTANT_ONLY_SLOT, "SECOND_STORAGE_LOCATION"),
                "Second.sol": storage_constant(CONSTANT_ONLY_SLOT),
            }
        )

        self.assertEqual(count, 3)
        self.assertEqual(
            sum("has no paired ERC-7201 namespace" in item for item in evidence), 3
        )
        same_file = next(item for item in evidence if "multiple times in" in item)
        cross_file = next(item for item in evidence if "across files" in item)
        self.assertRegex(same_file, r"First\.sol:1")
        self.assertRegex(same_file, r"First\.sol:2")
        self.assertNotRegex(same_file, r"Second\.sol:1")
        self.assertRegex(cross_file, r"First\.sol:1")
        self.assertRegex(cross_file, r"First\.sol:2")
        self.assertRegex(cross_file, r"Second\.sol:1")

    def test_unpaired_constant_is_indexed_for_reserved_collision(self):
        reserved_slot = next(iter(check_storage.RESERVED_SLOTS))
        count, evidence = self.analyze(
            {"ReservedConstant.sol": storage_constant(reserved_slot)}
        )

        self.assertEqual(count, 1)
        self.assertTrue(any("has no paired ERC-7201 namespace" in item for item in evidence))
        self.assertTrue(any("collides with reserved" in item for item in evidence))

    def test_source_order_pairing_preserves_later_pair_and_collision_indexing(self):
        source = (
            storage_constant(LEADING_SLOT, "LEADING_STORAGE_LOCATION")
            + "/// @custom:storage-location erc7201:sky.pau.storage.Orphan.v1\n"
            + "/// @custom:storage-location erc7201:sky.pau.storage.First.v1\n"
            + storage_constant(SLOT, "FIRST_STORAGE_LOCATION")
            + storage_constant(SLOT, "EXTRA_STORAGE_LOCATION")
            + "/// @custom:storage-location erc7201:sky.pau.storage.Later.v1\n"
            + storage_constant(LATER_SLOT, "LATER_STORAGE_LOCATION")
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SourceOrder.sol"
            path.write_text(source)
            declarations, unpaired_namespaces, unpaired_constants = (
                check_storage.declarations(path)
            )

        self.assertEqual(
            [declaration.namespace for declaration in declarations],
            [None, "sky.pau.storage.First.v1", None, "sky.pau.storage.Later.v1"],
        )
        self.assertEqual([declaration.line for declaration in declarations], [1, 4, 5, 7])
        self.assertEqual(len(unpaired_namespaces), 1)
        self.assertIn("sky.pau.storage.Orphan.v1", unpaired_namespaces[0])
        self.assertEqual(len(unpaired_constants), 2)
        self.assertRegex(unpaired_constants[0], r"SourceOrder\.sol:1:")
        self.assertRegex(unpaired_constants[1], r"SourceOrder\.sol:5:")

        count, evidence = self.analyze(
            {"SourceOrder.sol": source}, computed_slot=SLOT
        )
        self.assertEqual(count, 4)
        collision = next(item for item in evidence if "multiple times in" in item)
        self.assertRegex(collision, r"SourceOrder\.sol:4")
        self.assertRegex(collision, r"SourceOrder\.sol:5")

    def test_slot_mismatch_reports_path_and_line(self):
        count, evidence = self.analyze(
            {"Mismatch.sol": storage_declaration("sky.pau.storage.Mismatch.v1")},
            computed_slot=OTHER_SLOT,
        )

        self.assertEqual(count, 1)
        self.assertEqual(len(evidence), 1)
        self.assertRegex(evidence[0], r"Mismatch\.sol:2: declared")
        self.assertIn(f"computed {OTHER_SLOT}", evidence[0])

    def test_reserved_collision_reports_path_and_line(self):
        reserved_slot = next(iter(check_storage.RESERVED_SLOTS))
        _, evidence = self.analyze(
            {
                "Reserved.sol": storage_declaration(
                    "sky.pau.storage.Reserved.v1", reserved_slot
                )
            },
            computed_slot=reserved_slot,
        )

        self.assertEqual(len(evidence), 1)
        self.assertRegex(evidence[0], r"Reserved\.sol:2:")
        self.assertIn("collides with reserved SharedControllerStorage storage", evidence[0])

    def test_cross_file_collision_reports_both_locations(self):
        _, evidence = self.analyze(
            {
                "First.sol": storage_declaration("sky.pau.storage.First.v1"),
                "Second.sol": storage_declaration("sky.pau.storage.Second.v1"),
            }
        )

        self.assertEqual(len(evidence), 1)
        self.assertIn("is declared multiple times", evidence[0])
        self.assertRegex(evidence[0], r"First\.sol:2")
        self.assertRegex(evidence[0], r"Second\.sol:2")

    def test_same_file_collision_reports_each_line(self):
        source = (
            storage_declaration("sky.pau.storage.First.v1")
            + "\n"
            + storage_declaration("sky.pau.storage.Second.v1")
        )
        _, evidence = self.analyze({"Duplicate.sol": source})

        self.assertEqual(len(evidence), 1)
        self.assertIn("is declared multiple times", evidence[0])
        self.assertRegex(evidence[0], r"Duplicate\.sol:2")
        self.assertRegex(evidence[0], r"Duplicate\.sol:5")

    def test_findings_are_advisory_and_exit_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Mismatch.sol"
            path.write_text(storage_declaration("sky.pau.storage.Mismatch.v1"))
            output = io.StringIO()
            with mock.patch.object(check_storage, "erc7201_slot", return_value=OTHER_SLOT):
                with mock.patch.object(sys, "argv", ["check_storage.py", str(path)]):
                    with contextlib.redirect_stdout(output):
                        result = check_storage.main()

        self.assertEqual(result, 0)
        self.assertIn("declared", output.getvalue())
        self.assertIn("does not produce a verdict", output.getvalue())


if __name__ == "__main__":
    unittest.main()
