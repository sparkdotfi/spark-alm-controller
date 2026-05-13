// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUFactory } from "../../src/interfaces/IPAUFactory.sol";

import { IAccessControls } from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }       from "../../src/interfaces/IALMProxy.sol";
import { IController }     from "../../src/interfaces/IController.sol";
import { IRateLimits }     from "../../src/interfaces/IRateLimits.sol";

import { PAUFactory } from "../../src/PAUFactory.sol";

contract PAUFactory_IntegrationTests is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE   = 0x00;

    address internal admin          = makeAddr("admin");
    address internal allocator      = makeAddr("allocator");
    address internal allocatorAdmin = makeAddr("allocatorAdmin");
    address internal beacon         = makeAddr("beacon");
    address internal unauthorized   = makeAddr("unauthorized");

    PAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() external {
        factory = new PAUFactory(beacon);
    }

    /**********************************************************************************************/
    /*** Initial State Tests                                                                    ***/
    /**********************************************************************************************/

    function test_initialState() external {
        assertEq(factory.beacon(), beacon);
    }

    /**********************************************************************************************/
    /*** deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function test_deploy() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedAlmProxy       = vm.computeCreateAddress(address(factory), nonce);
        address expectedRateLimits     = vm.computeCreateAddress(address(factory), nonce + 1);
        address expectedAccessControls = vm.computeCreateAddress(address(factory), nonce + 2);
        address expectedController     = vm.computeCreateAddress(address(factory), nonce + 3);

        vm.expectEmit(address(factory));
        emit IPAUFactory.PAUDeployed(
            admin,
            expectedController,
            expectedAccessControls,
            expectedAlmProxy,
            expectedRateLimits
        );

        vm.prank(admin);
        IController controller = IController(payable(factory.deploy(admin)));

        IAccessControls accessControls = IAccessControls(controller.accessControls());
        IALMProxy       almProxy       = IALMProxy(payable(controller.proxy()));
        IRateLimits     rateLimits     = IRateLimits(controller.rateLimits());

        // Controller references are wired correctly.

        assertEq(address(accessControls), expectedAccessControls);
        assertEq(address(almProxy),       expectedAlmProxy);
        assertEq(address(rateLimits),     expectedRateLimits);

        // CONTROLLER role granted on ALMProxy and RateLimits to the Controller.

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     address(controller)), true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(controller)), true);

        // DEFAULT_ADMIN_ROLE granted to admin on all three.

        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE,       admin), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     admin), true);

        // Only one admin member on IAccessControls (ALMProxy and RateLimits ACL is not enumerable).

        assertEq(accessControls.getRoleMember(DEFAULT_ADMIN_ROLE, 0), admin);

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        // Factory has NO DEFAULT_ADMIN_ROLE on any contract.

        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(factory)), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE,       address(factory)), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     address(factory)), false);

        // Factory has NO CONTROLLER role on ALMProxy or RateLimits.

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     address(factory)), false);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(factory)), false);

        // Admin can grant roles on IAccessControls.

        vm.startPrank(admin);

        accessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role 
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,       allocator),      true);
        assertEq(accessControls.hasRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin), true);

        // Admin can grant CONTROLLER role on ALMProxy and RateLimits.

        address newController = makeAddr("newController");

        almProxy.grantRole(almProxy.CONTROLLER(),     newController);
        rateLimits.grantRole(rateLimits.CONTROLLER(), newController);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     newController), true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), newController), true);

        vm.stopPrank();
    }

    function test_deploy_multipleDeployments() external {
        IController controller1 = IController(payable(factory.deploy(admin)));
        IController controller2 = IController(payable(factory.deploy(admin)));

        // Each deployment produces distinct controller addresses.
        assertNotEq(address(controller1), address(controller2));

        // Each deployment produces distinct sub-contract addresses.
        assertNotEq(controller1.accessControls(), controller2.accessControls());
        assertNotEq(controller1.proxy(),          controller2.proxy());
        assertNotEq(controller1.rateLimits(),     controller2.rateLimits());
    }

}
