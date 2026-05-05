// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl }           from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

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
    /*** grantRole Tests                                                                        ***/
    /**********************************************************************************************/

    function test_grantRole_notDefaultAdmin() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            deployer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(deployer);
        accessControls.grantRole(ALLOCATOR_ROLE, allocator);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(unauthorized);
        accessControls.grantRole(ALLOCATOR_ROLE, allocator);
    }

    function test_grantRole_notRoleAdmin() external {
        accessControls.__grantRole(FREEZER_ROLE,      freezer);
        accessControls.__setRoleAdmin(ALLOCATOR_ROLE, FREEZER_ROLE);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(freezer);
        accessControls.grantRole(ALLOCATOR_ROLE, allocator);
    }

    function test_grantRole() external {
        vm.expectEmit();
        emit IAccessControl.RoleGranted(ALLOCATOR_ROLE, allocator, admin);

        vm.prank(admin);
        accessControls.grantRole(ALLOCATOR_ROLE, allocator);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE, allocator), true);
    }

    /**********************************************************************************************/
    /*** revokeRole Tests                                                                       ***/
    /**********************************************************************************************/

    function test_revokeRole_notRoleAdminOrDefaultAdmin() external {
        accessControls.__setRoleAdmin(ALLOCATOR_ROLE, FREEZER_ROLE);

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControls.NotRoleAdminOrDefaultAdmin.selector,
            deployer,
            ALLOCATOR_ROLE,
            FREEZER_ROLE
        ));
        vm.prank(deployer);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);

        vm.expectRevert(abi.encodeWithSelector(
            IAccessControls.NotRoleAdminOrDefaultAdmin.selector,
            unauthorized,
            ALLOCATOR_ROLE,
            FREEZER_ROLE
        ));
        vm.prank(unauthorized);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);
    }

    function test_revokeRole_roleNotGranted() external {
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControls.RoleNotGranted.selector,
            allocator,
            ALLOCATOR_ROLE
        ));
        vm.prank(admin);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);
    }

    function test_revokeRole_byDefaultAdmin() external {
        accessControls.__grantRole(ALLOCATOR_ROLE, allocator);

        vm.expectEmit();
        emit IAccessControl.RoleRevoked(ALLOCATOR_ROLE, allocator, admin);

        vm.prank(admin);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE, allocator), false);
    }

    function test_revokeRole_byRoleAdmin() external {
        accessControls.__grantRole(ALLOCATOR_ROLE,    allocator);
        accessControls.__grantRole(FREEZER_ROLE,      freezer);
        accessControls.__setRoleAdmin(ALLOCATOR_ROLE, FREEZER_ROLE);

        vm.expectEmit();
        emit IAccessControl.RoleRevoked(ALLOCATOR_ROLE, allocator, freezer);

        vm.prank(freezer);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE, allocator), false);
    }

    /**********************************************************************************************/
    /*** setRoleRevoker Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setRoleRevoker_notDefaultAdmin() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            deployer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(deployer);
        accessControls.setRoleRevoker(ALLOCATOR_ROLE, FREEZER_ROLE);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(unauthorized);
        accessControls.setRoleRevoker(ALLOCATOR_ROLE, FREEZER_ROLE);
    }

    function test_setRoleRevoker() external {
        vm.expectEmit();
        emit IAccessControl.RoleAdminChanged(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE, FREEZER_ROLE);

        vm.prank(admin);
        accessControls.setRoleRevoker(ALLOCATOR_ROLE, FREEZER_ROLE);

        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE),   FREEZER_ROLE);
        assertEq(accessControls.getRoleRevoker(ALLOCATOR_ROLE), FREEZER_ROLE);

        vm.expectEmit();
        emit IAccessControl.RoleAdminChanged(ALLOCATOR_ROLE, FREEZER_ROLE, DEFAULT_ADMIN_ROLE);

        vm.prank(admin);
        accessControls.setRoleRevoker(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE);

        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE),   DEFAULT_ADMIN_ROLE);
        assertEq(accessControls.getRoleRevoker(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);
    }

    /**********************************************************************************************/
    /*** getRoleRevoker Tests                                                                   ***/
    /**********************************************************************************************/

    function test_getRoleRevoker() external {
        assertEq(accessControls.getRoleRevoker(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);

        accessControls.__setRoleAdmin(ALLOCATOR_ROLE, FREEZER_ROLE);

        assertEq(accessControls.getRoleRevoker(ALLOCATOR_ROLE), FREEZER_ROLE);

        accessControls.__setRoleAdmin(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE);

        assertEq(accessControls.getRoleRevoker(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);
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
