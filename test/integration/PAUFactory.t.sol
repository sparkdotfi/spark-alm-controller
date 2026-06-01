// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUFactory } from "../../src/interfaces/IPAUFactory.sol";

import { IAccessControls }    from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }          from "../../src/interfaces/IALMProxy.sol";
import { IALMProxyFreezable } from "../../src/interfaces/IALMProxyFreezable.sol";
import { IController }        from "../../src/interfaces/IController.sol";
import { IRateLimits }        from "../../src/interfaces/IRateLimits.sol";

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
    /*** deployAccessControls Tests                                                             ***/
    /**********************************************************************************************/

    function test_deployAccessControls() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedAccessControls = vm.computeCreateAddress(address(factory), nonce);

        vm.expectEmit(address(factory));
        emit IPAUFactory.AccessControlsDeployed(expectedAccessControls);

        address accessControls = factory.deployAccessControls(admin);

        assertEq(accessControls, expectedAccessControls);

        assertEq(IAccessControls(accessControls).hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** deployController Tests                                                                 ***/
    /**********************************************************************************************/

    function test_deployController() external {
        address accessControls = makeAddr("accessControls");
        address almProxy       = makeAddr("almProxy");
        address rateLimits     = makeAddr("rateLimits");

        uint256 nonce = vm.getNonce(address(factory));

        address expectedController = vm.computeCreateAddress(address(factory), nonce);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ControllerDeployed(expectedController, accessControls, almProxy, rateLimits);

        address controller = factory.deployController(accessControls, almProxy, rateLimits);

        assertEq(controller, expectedController);

        assertEq(IController(controller).accessControls(), accessControls);
        assertEq(IController(controller).beacon(),         beacon);
        assertEq(IController(controller).proxy(),          almProxy);
        assertEq(IController(controller).rateLimits(),     rateLimits);
    }

    /**********************************************************************************************/
    /*** deployALMProxy Tests                                                                   ***/
    /**********************************************************************************************/

    function test_deployALMProxy() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedALMProxy = vm.computeCreateAddress(address(factory), nonce);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ALMProxyDeployed(expectedALMProxy);

        address almProxy = factory.deployALMProxy(admin);

        assertEq(almProxy, expectedALMProxy);

        assertEq(IALMProxy(almProxy).hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** deployALMProxyFreezable Tests                                                          ***/
    /**********************************************************************************************/

    function test_deployALMProxyFreezable() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedALMProxyFreezable = vm.computeCreateAddress(address(factory), nonce);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ALMProxyFreezableDeployed(expectedALMProxyFreezable);

        address almProxyFreezable = factory.deployALMProxyFreezable(admin);

        assertEq(almProxyFreezable, expectedALMProxyFreezable);

        assertEq(IALMProxyFreezable(almProxyFreezable).hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** deployRateLimits Tests                                                                 ***/
    /**********************************************************************************************/

    function test_deployRateLimits() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedRateLimits = vm.computeCreateAddress(address(factory), nonce);

        vm.expectEmit(address(factory));
        emit IPAUFactory.RateLimitsDeployed(expectedRateLimits);

        address rateLimits = factory.deployRateLimits(admin);

        assertEq(rateLimits, expectedRateLimits);

        assertEq(IRateLimits(rateLimits).hasRole(DEFAULT_ADMIN_ROLE, admin), true);
    }

    /**********************************************************************************************/
    /*** full deploy Tests                                                                      ***/
    /**********************************************************************************************/

    function test_deploy() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedAlmProxy       = vm.computeCreateAddress(address(factory), nonce);
        address expectedRateLimits     = vm.computeCreateAddress(address(factory), nonce + 1);
        address expectedAccessControls = vm.computeCreateAddress(address(factory), nonce + 2);
        address expectedController     = vm.computeCreateAddress(address(factory), nonce + 3);

        IALMProxy       almProxy       = IALMProxy(factory.deployALMProxy(admin));
        IRateLimits     rateLimits     = IRateLimits(factory.deployRateLimits(admin));
        IAccessControls accessControls = IAccessControls(factory.deployAccessControls(admin));

        address controller = factory.deployController(address(accessControls), address(almProxy), address(rateLimits));

        assertEq(address(almProxy),       expectedAlmProxy);
        assertEq(address(rateLimits),     expectedRateLimits);
        assertEq(address(accessControls), expectedAccessControls);
        assertEq(controller,              expectedController);

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

        // Admin can grant roles.

        vm.startPrank(admin);

        almProxy.grantRole(almProxy.CONTROLLER(),     controller);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller);

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

    function test_deploy_multiController() external {
        uint256 nonce = vm.getNonce(address(factory));

        address expectedAlmProxy       = vm.computeCreateAddress(address(factory), nonce);
        address expectedRateLimits     = vm.computeCreateAddress(address(factory), nonce + 1);
        address expectedAccessControls = vm.computeCreateAddress(address(factory), nonce + 2);
        address expectedController1    = vm.computeCreateAddress(address(factory), nonce + 3);
        address expectedController2    = vm.computeCreateAddress(address(factory), nonce + 4);

        IALMProxy       almProxy       = IALMProxy(factory.deployALMProxy(admin));
        IRateLimits     rateLimits     = IRateLimits(factory.deployRateLimits(admin));
        IAccessControls accessControls = IAccessControls(factory.deployAccessControls(admin));

        address controller1 = factory.deployController(address(accessControls), address(almProxy), address(rateLimits));
        address controller2 = factory.deployController(address(accessControls), address(almProxy), address(rateLimits));

        assertEq(address(almProxy),       expectedAlmProxy);
        assertEq(address(rateLimits),     expectedRateLimits);
        assertEq(address(accessControls), expectedAccessControls);
        assertEq(controller1,             expectedController1);
        assertEq(controller2,             expectedController2);

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

        // Admin can grant roles.

        vm.startPrank(admin);

        almProxy.grantRole(almProxy.CONTROLLER(),     controller1);
        almProxy.grantRole(almProxy.CONTROLLER(),     controller2);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller1);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller2);

        accessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,       allocator),      true);
        assertEq(accessControls.hasRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin), true);

        vm.stopPrank();
    }

}
