// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Controller } from "../../src/Controller.sol";

contract ControllerHarness is Controller {

    constructor(address accessControls_, address proxy_, address rateLimits_)
        Controller(accessControls_, proxy_, rateLimits_) {}

    function accessControls() public view returns (address) {
        return _getControllerStorage().accessControls;
    }

    function proxy() public view returns (address) {
        return _getControllerStorage().proxy;
    }

    function rateLimits() public view returns (address) {
        return _getControllerStorage().rateLimits;
    }

}

contract Controller_Tests is Test {

    function test_constructor() external {
        address accessControls = makeAddr("accessControls");
        address proxy          = makeAddr("proxy");
        address rateLimits     = makeAddr("rateLimits");

        ControllerHarness controller = new ControllerHarness(accessControls, proxy, rateLimits);

        assertEq(controller.accessControls(), accessControls);
        assertEq(controller.proxy(),          proxy);
        assertEq(controller.rateLimits(),     rateLimits);
    }

}
