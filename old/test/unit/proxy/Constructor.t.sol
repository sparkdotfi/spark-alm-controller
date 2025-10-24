// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxy } from "../../../src/ALMProxy.sol";

import "../UnitTestBase.t.sol";

contract ALMProxyConstructorTests is UnitTestBase {

    function test_constructor() public {
        ALMProxy newAlmProxy = new ALMProxy(admin);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

}
