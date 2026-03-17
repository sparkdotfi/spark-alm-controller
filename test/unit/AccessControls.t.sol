// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl }           from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import { IAccessControls } from "../../src/interfaces/IAccessControls.sol";

import { AccessControls } from "../../src/AccessControls.sol";

contract AccessControls_Tests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal admin        = makeAddr("admin");
    address internal freezer      = makeAddr("freezer");
    address internal relayer      = makeAddr("relayer");
    address internal deployer     = makeAddr("deployer");
    address internal unauthorized = makeAddr("unauthorized");

    AccessControls internal accessControls;

    function setUp() external {
        vm.prank(deployer);
        accessControls = new AccessControls(admin);
    }

    function test_constructor() external view {
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    function test_removeRelayer_notFreezer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                accessControls.FREEZER_ROLE()
            )
        );

        vm.prank(unauthorized);
        accessControls.removeRelayer(relayer);
    }

    function test_removeRelayer() external {
        vm.startPrank(admin);
        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        vm.stopPrank();

        assertEq(accessControls.hasRole(accessControls.RELAYER_ROLE(), relayer), true);

        vm.expectEmit(address(accessControls));
        emit IAccessControl.RoleRevoked(accessControls.RELAYER_ROLE(), relayer, freezer);

        vm.expectEmit(address(accessControls));
        emit IAccessControls.RelayerRemoved(relayer);

        vm.prank(freezer);
        accessControls.removeRelayer(relayer);

        assertEq(accessControls.hasRole(accessControls.RELAYER_ROLE(), relayer), false);
    }

    function test_supportsInterface() external view {
        assertEq(accessControls.supportsInterface(type(IAccessControls).interfaceId),          true);
        assertEq(accessControls.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(accessControls.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(accessControls.supportsInterface(type(IERC165).interfaceId),                  true);
    }

}
