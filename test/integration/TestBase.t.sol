// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { RateLimits }     from "../../src/RateLimits.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";

abstract contract Controller_TestBase is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    address internal admin          = makeAddr("admin");
    address internal facetValidator = makeAddr("facetValidator");
    address internal factoryAdmin   = makeAddr("factoryAdmin");
    address internal freezer        = makeAddr("freezer");
    address internal relayer        = makeAddr("relayer");
    address internal unauthorized   = makeAddr("unauthorized");

    PAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function _deploy() internal returns (address controller) {
        AccessControls accessControls = new AccessControls(admin);
        ALMProxy       proxy          = new ALMProxy(admin);
        RateLimits     rateLimits     = new RateLimits(admin);

        factory = new PAUFactory(factoryAdmin, facetValidator);

        controller = address(new Controller(
            address(accessControls),
            address(factory),
            address(proxy),
            address(rateLimits)
        ));

        vm.startPrank(admin);
        proxy.grantRole(proxy.CONTROLLER(), controller);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        vm.stopPrank();

        vm.label(address(accessControls), "AccessControls");
        vm.label(admin,                   "Admin");
        vm.label(controller,              "Controller");
        vm.label(address(proxy),          "Proxy");
        vm.label(address(rateLimits),     "RateLimits");
        vm.label(unauthorized,            "Unauthorized");
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
