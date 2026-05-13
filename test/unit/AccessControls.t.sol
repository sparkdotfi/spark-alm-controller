// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl }           from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import { IAccessControls } from "../../src/interfaces/IAccessControls.sol";

import { AccessControls } from "../../src/AccessControls.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract AccessControlsHarness is AccessControls {

    constructor(address admin) AccessControls(admin) {}

    function __grantRole(bytes32 role, address account) external {
        _grantRole(role, account);
    }

    function __setRoleAdmin(bytes32 role, bytes32 adminRole) external {
        _setRoleAdmin(role, adminRole);
    }

}

contract AccessControls_Tests is UnitTestBase {

    address internal deployer = makeAddr("deployer");

    AccessControlsHarness internal accessControls;

    function setUp() external {
        vm.prank(deployer);
        accessControls = new AccessControlsHarness(admin);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IAccessControls.ZeroAdmin.selector);
        new AccessControls(address(0));
    }

    function test_constructor() external {
        vm.expectEmit();
        emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, admin, deployer);

        vm.prank(deployer);
        AccessControls accessControls_ = new AccessControls(admin);

        assertEq(accessControls_.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** setRoleAdmin Tests                                                                     ***/
    /**********************************************************************************************/

    function test_setRoleAdmin_unauthorized() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);
    }

    function test_setRoleAdmin() external {
        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);

        vm.expectEmit();
        emit IAccessControl.RoleAdminChanged(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE, ALLOCATOR_ADMIN_ROLE);

        vm.prank(admin);
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE), ALLOCATOR_ADMIN_ROLE);

        vm.expectEmit();
        emit IAccessControl.RoleAdminChanged(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

        vm.prank(admin);
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE);

        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);
    }

    /**********************************************************************************************/
    /*** supportsInterface Tests                                                                ***/
    /**********************************************************************************************/

    function test_supportsInterface() external view {
        assertEq(accessControls.supportsInterface(type(IAccessControls).interfaceId),          true);
        assertEq(accessControls.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(accessControls.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(accessControls.supportsInterface(type(IERC165).interfaceId),                  true);
        assertEq(accessControls.supportsInterface(0x00000000),                                 false);
        assertEq(accessControls.supportsInterface(0xffffffff),                                 false);
    }

}
