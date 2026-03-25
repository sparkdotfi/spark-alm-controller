// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { Controller }     from "../../src/Controller.sol";

contract ControllerTestBase is Test {

    /**********************************************************************************************/
    /*** Declarations and Setup                                                                 ***/
    /**********************************************************************************************/

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    AccessControls internal accessControls;

    address internal controllerAddress;

    address internal admin        = makeAddr("admin");
    address internal proxy        = makeAddr("proxy");
    address internal rateLimits   = makeAddr("rateLimits");
    address internal unauthorized = makeAddr("unauthorized");

    function setUp() public virtual {
        // Step-1: Deploy the controller and its dependencies.

        accessControls = new AccessControls(admin);

        controllerAddress = address(new Controller(address(accessControls), proxy, rateLimits));

        // Step-2: Label addresses.

        vm.label(address(accessControls), "AccessControls");
        vm.label(admin,                   "Admin");
        vm.label(controllerAddress,       "Controller");
        vm.label(proxy,                   "Proxy");
        vm.label(rateLimits,              "RateLimits");
        vm.label(unauthorized,            "Unauthorized");
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setControllerEntered() internal virtual {
        vm.store(controllerAddress, _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(controllerAddress);
    }

    function _assertReentrancyGuardWrittenToTwice(address controller_) internal {
        ( , bytes32[] memory writeSlots ) = vm.accesses(controller_);

        uint256 count = 0;

        for (uint256 i = 0; i < writeSlots.length; ++i) {
            if (writeSlots[i] != _REENTRANCY_GUARD_SLOT) continue;

            ++count;
        }

        assertEq(count, 2);
        assertEq(vm.load(controller_, _REENTRANCY_GUARD_SLOT), _REENTRANCY_GUARD_NOT_ENTERED);
    }

}
