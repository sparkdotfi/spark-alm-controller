// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }          from "../../../src/interfaces/IALMProxy.sol";
import { IALMProxyFreezable } from "../../../src/interfaces/IALMProxyFreezable.sol";

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ALMProxyFreezable } from "../../../src/ALMProxyFreezable.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

contract ALMProxy_Constructor_Tests is UnitTestBase {

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IALMProxy.ZeroAdmin.selector);
        new ALMProxy(address(0));
    }

    function test_constructor() external {
        ALMProxy newAlmProxy = new ALMProxy(admin);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

}

contract ALMProxyFreezable_Constructor_Tests is UnitTestBase {

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IALMProxyFreezable.ZeroAdmin.selector);
        new ALMProxyFreezable(address(0));
    }

    function test_constructor() external {
        ALMProxyFreezable newAlmProxyFreezable = new ALMProxyFreezable(admin);

        assertEq(newAlmProxyFreezable.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

}
