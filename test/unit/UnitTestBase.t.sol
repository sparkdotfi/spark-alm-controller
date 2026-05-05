// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

abstract contract UnitTestBase is Test {

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant ALLOCATOR_ROLE  = keccak256("ALLOCATOR_ROLE");
    bytes32 constant CONTROLLER_ROLE = keccak256("CONTROLLER");
    bytes32 constant FREEZER_ROLE    = keccak256("FREEZER_ROLE");

    address internal admin        = makeAddr("admin");
    address internal allocator    = makeAddr("allocator");
    address internal freezer      = makeAddr("freezer");
    address internal unauthorized = makeAddr("unauthorized");

    function _assertReentrancyGuardWrittenToTwice(address instance) internal {
        ( , bytes32[] memory writeSlots ) = vm.accesses(instance);

        uint256 count = 0;

        for (uint256 i = 0; i < writeSlots.length; ++i) {
            if (writeSlots[i] != _REENTRANCY_GUARD_SLOT) continue;

            ++count;
        }

        assertEq(count, 2);
        assertEq(vm.load(instance, _REENTRANCY_GUARD_SLOT), _REENTRANCY_GUARD_NOT_ENTERED);
    }

}
