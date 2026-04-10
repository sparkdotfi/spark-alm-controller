// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControls } from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }       from "../../src/interfaces/IALMProxy.sol";
import { IController }     from "../../src/interfaces/IController.sol";
import { IPAUFactory }     from "../../src/interfaces/IPAUFactory.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

abstract contract Integration_TestBase is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    address internal admin        = makeAddr("admin");
    address internal beaconAdmin  = makeAddr("beaconAdmin");
    address internal freezer      = makeAddr("freezer");
    address internal relayer      = makeAddr("relayer");
    address internal unauthorized = makeAddr("unauthorized");

    Beacon     internal beacon;
    PAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function _deploy() internal returns (address controller) {
        beacon  = new Beacon(beaconAdmin);
        factory = new PAUFactory(address(beacon));

        controller = factory.deploy(admin);

        IAccessControls accessControls = IAccessControls(IController(payable(controller)).accessControls());

        vm.startPrank(admin);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        vm.stopPrank();

        vm.label(address(beacon),                               "Beacon");
        vm.label(address(factory),                              "Factory");
        vm.label(address(accessControls),                       "AccessControls");
        vm.label(admin,                                         "Admin");
        vm.label(controller,                                    "Controller");
        vm.label(IController(payable(controller)).proxy(),      "Proxy");
        vm.label(IController(payable(controller)).rateLimits(), "RateLimits");
        vm.label(unauthorized,                                  "Unauthorized");
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setEntered(address controller_) internal virtual {
        vm.store(controller_, _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
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
