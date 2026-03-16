// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Controller } from "../../src/Controller.sol";

contract ControllerHarness is Controller {

    constructor(address proxy_, address rateLimits_) Controller(proxy_, rateLimits_) {}

    function proxy() public view returns (address) {
        return _getControllerStorage().proxy;
    }

    function rateLimits() public view returns (address) {
        return _getControllerStorage().rateLimits;
    }

}

contract Controller_Tests is Test {

    function test_constructor() external {
        address proxy      = makeAddr("proxy");
        address rateLimits = makeAddr("rateLimits");

        ControllerHarness controller = new ControllerHarness(proxy, rateLimits);

        assertEq(controller.proxy(),      proxy);
        assertEq(controller.rateLimits(), rateLimits);
    }

}
