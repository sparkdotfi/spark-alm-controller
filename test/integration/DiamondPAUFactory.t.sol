// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDiamondPAUFactory }  from "../../src/interfaces/IDiamondPAUFactory.sol";

import { AccessControls }    from "../../src/AccessControls.sol";
import { ALMProxy }          from "../../src/ALMProxy.sol";
import { Controller }        from "../../src/Controller.sol";
import { DiamondPAUFactory } from "../../src/DiamondPAUFactory.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

contract DiamondPAUFactory_Tests is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal admin         = makeAddr("admin");
    address internal freezer       = makeAddr("freezer");
    address internal newController = makeAddr("newController");
    address internal relayer       = makeAddr("relayer");

    DiamondPAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() external {
        factory = new DiamondPAUFactory();
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
        emit IDiamondPAUFactory.DiamondPAUDeployed(
            admin,
            expectedController,
            expectedAccessControls,
            expectedAlmProxy,
            expectedRateLimits
        );

        address controllerAddress = factory.deploy(admin);

        Controller     controller     = Controller(payable(controllerAddress));
        AccessControls accessControls = AccessControls(controller.accessControls());
        ALMProxy       almProxy       = ALMProxy(payable(controller.proxy()));
        RateLimits     rateLimits     = RateLimits(controller.rateLimits());

        // Controller references are wired correctly.

        assertEq(address(accessControls), expectedAccessControls);
        assertEq(address(almProxy),       expectedAlmProxy);
        assertEq(address(rateLimits),     expectedRateLimits);

        // CONTROLLER role granted on ALMProxy and RateLimits to the Controller.

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     controllerAddress), true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), controllerAddress), true);

        // DEFAULT_ADMIN_ROLE granted to admin on all three.

        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE,       admin), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     admin), true);

        // Only one admin member on AccessControls (ALMProxy and RateLimits ACL is not enumerable).

        assertEq(accessControls.getRoleMember(DEFAULT_ADMIN_ROLE, 0), admin);

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        // Factory has NO DEFAULT_ADMIN_ROLE on any contract.

        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(factory)), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE,       address(factory)), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     address(factory)), false);

        // Factory has NO CONTROLLER role on ALMProxy or RateLimits.

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     address(factory)), false);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), address(factory)), false);

        // Admin can grant roles on AccessControls.

        vm.startPrank(admin);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);

        assertEq(accessControls.hasRole(accessControls.FREEZER_ROLE(), freezer), true);
        assertEq(accessControls.hasRole(accessControls.RELAYER_ROLE(), relayer), true);

        // Admin can grant CONTROLLER role on ALMProxy and RateLimits.

        almProxy.grantRole(almProxy.CONTROLLER(),     newController);
        rateLimits.grantRole(rateLimits.CONTROLLER(), newController);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     newController), true);
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), newController), true);

        vm.stopPrank();
    }

    function test_deploy_multipleDeployments() external {
        Controller controller1 = Controller(payable(factory.deploy(admin)));
        Controller controller2 = Controller(payable(factory.deploy(admin)));

        // Each deployment produces distinct controller addresses.
        assertNotEq(address(controller1), address(controller2));

        // Each deployment produces distinct sub-contract addresses.
        assertNotEq(controller1.accessControls(), controller2.accessControls());
        assertNotEq(controller1.proxy(),          controller2.proxy());
        assertNotEq(controller1.rateLimits(),     controller2.rateLimits());
    }

}
