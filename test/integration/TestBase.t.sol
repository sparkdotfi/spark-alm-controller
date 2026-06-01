// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControls } from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }       from "../../src/interfaces/IALMProxy.sol";
import { IController }     from "../../src/interfaces/IController.sol";
import { IPAUFactory }     from "../../src/interfaces/IPAUFactory.sol";
import { IRateLimits }     from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

abstract contract Integration_TestBase is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE   = 0x00;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    address internal admin          = makeAddr("admin");
    address internal allocator      = makeAddr("allocator");
    address internal allocatorAdmin = makeAddr("allocatorAdmin");
    address internal beaconAdmin    = makeAddr("beaconAdmin");
    address internal unauthorized   = makeAddr("unauthorized");

    Beacon     internal beacon;
    PAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function _deploy() internal returns (address controller) {
        beacon  = new Beacon(beaconAdmin);
        factory = new PAUFactory(address(beacon));

        IRateLimits     rateLimits     = IRateLimits(factory.deployRateLimits(admin));
        IAccessControls accessControls = IAccessControls(factory.deployAccessControls(admin));
        IALMProxy       almProxy       = IALMProxy(factory.deployALMProxy(admin));

        controller = factory.deployController(address(accessControls), address(almProxy), address(rateLimits));

        vm.startPrank(admin);

        accessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        almProxy.grantRole(almProxy.CONTROLLER(),     controller);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller);

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
