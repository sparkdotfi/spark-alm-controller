// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract MainnetController_Constructor_Tests is UnitTestBase {

    function test_constructor() public {
        MainnetController mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            makeAddr("accessControls")
        );

        assertEq(mainnetController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(mainnetController.proxy()),      makeAddr("almProxy"));
        assertEq(address(mainnetController.rateLimits()), makeAddr("rateLimits"));
    }

}

contract ForeignController_Constructor_Tests is UnitTestBase {

    address almProxy   = makeAddr("almProxy");
    address rateLimits = makeAddr("rateLimits");

    function test_constructor() public {
        ForeignController foreignController = new ForeignController(
            admin,
            almProxy,
            rateLimits,
            makeAddr("accessControls")
        );

        assertEq(foreignController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(foreignController.proxy()),      almProxy);
        assertEq(address(foreignController.rateLimits()), rateLimits);
    }

}
