// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

contract UnitTestBase is Test {

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant CONTROLLER = keccak256("CONTROLLER");
    bytes32 constant FREEZER    = keccak256("FREEZER");
    bytes32 constant RELAYER    = keccak256("RELAYER");

    address admin   = makeAddr("admin");
    address freezer = makeAddr("freezer");
    address relayer = makeAddr("relayer");

}
