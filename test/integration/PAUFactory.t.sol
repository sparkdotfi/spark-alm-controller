// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IPAUFactory }  from "../../src/interfaces/IPAUFactory.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";
import { RateLimits }     from "../../src/RateLimits.sol";

contract MockFacet1 {

    function foo() external pure returns (bool) {
        return true;
    }

}

contract MockFacet2 {

    function bar() external pure returns (bool) {
        return false;
    }

}

contract PAUFactory_Tests is Test {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    bytes32 internal constant DEFAULT_ADMIN_ROLE   = 0x00;
    bytes32 internal constant FACET_VALIDATOR_ROLE = keccak256("FACET_VALIDATOR_ROLE");

    address internal admin          = makeAddr("admin");
    address internal facetValidator = makeAddr("facetValidator");
    address internal factoryAdmin   = makeAddr("factoryAdmin");
    address internal freezer        = makeAddr("freezer");
    address internal newController  = makeAddr("newController");
    address internal relayer        = makeAddr("relayer");
    address internal unauthorized   = makeAddr("unauthorized");

    PAUFactory internal factory;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() external {
        factory = new PAUFactory(factoryAdmin, facetValidator);
    }

    /**********************************************************************************************/
    /*** Initial State Tests                                                                    ***/
    /**********************************************************************************************/

    function test_initialState() external {
        assertEq(factory.FACET_VALIDATOR_ROLE(), FACET_VALIDATOR_ROLE);

        assertEq(factory.hasRole(DEFAULT_ADMIN_ROLE,   factoryAdmin),   true);
        assertEq(factory.hasRole(FACET_VALIDATOR_ROLE, facetValidator), true);

        assertEq(factory.getRoleMemberCount(DEFAULT_ADMIN_ROLE),   1);
        assertEq(factory.getRoleMemberCount(FACET_VALIDATOR_ROLE), 1);
    }

    /**********************************************************************************************/
    /*** setValidFacet Tests                                                                    ***/
    /**********************************************************************************************/

    function test_setValidFacet_notFacetValidator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                FACET_VALIDATOR_ROLE
            )
        );

        vm.prank(unauthorized);
        factory.setValidFacet(address(0), false);
    }

    function test_setValidFacet_zeroFacet() external {
        vm.expectRevert(IPAUFactory.ZeroFacet.selector);
        vm.prank(facetValidator);
        factory.setValidFacet(address(0), false);
    }

    function test_setValidFacet_emptyFacet() external {
        vm.expectRevert(IPAUFactory.EmptyFacet.selector);
        vm.prank(facetValidator);
        factory.setValidFacet(makeAddr("emptyFacet"), false);
    }

    function test_setValidFacet() external {
        address facet = address(new MockFacet1());

        assertEq(factory.isValidFacet(facet), false);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facet, true);

        vm.prank(facetValidator);
        factory.setValidFacet(facet, true);

        assertEq(factory.isValidFacet(facet), true);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facet, false);

        vm.prank(facetValidator);
        factory.setValidFacet(facet, false);

        assertEq(factory.isValidFacet(facet), false);
    }

    /**********************************************************************************************/
    /*** setValidFacets Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setValidFacets_notFacetValidator() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                FACET_VALIDATOR_ROLE
            )
        );

        vm.prank(unauthorized);
        factory.setValidFacets(new address[](0), new bool[](0));
    }

    function test_setValidFacets_zeroFacet() external {
        address facet = address(new MockFacet1());

        address[] memory facets = new address[](2);
        facets[0] = address(0);
        facets[1] = facet;

        vm.expectRevert(IPAUFactory.ZeroFacet.selector);
        vm.prank(facetValidator);
        factory.setValidFacets(facets, new bool[](2));

        facets[0] = facet;
        facets[1] = address(0);

        vm.expectRevert(IPAUFactory.ZeroFacet.selector);
        vm.prank(facetValidator);
        factory.setValidFacets(facets, new bool[](2));
    }

    function test_setValidFacets() external {
        address[] memory facets = new address[](2);
        facets[0] = address(new MockFacet1());
        facets[1] = address(new MockFacet2());

        assertEq(factory.isValidFacet(facets[0]), false);
        assertEq(factory.isValidFacet(facets[1]), false);

        bool[] memory valid = new bool[](2);
        valid[0] = true;
        valid[1] = true;

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facets[0], true);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facets[1], true);

        vm.prank(facetValidator);
        factory.setValidFacets(facets, valid);

        assertEq(factory.isValidFacet(facets[0]), true);
        assertEq(factory.isValidFacet(facets[1]), true);

        valid[0] = false;
        valid[1] = false;

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facets[0], false);

        vm.expectEmit(address(factory));
        emit IPAUFactory.ValidFacetSet(facets[1], false);

        vm.prank(facetValidator);
        factory.setValidFacets(facets, valid);

        assertEq(factory.isValidFacet(facets[0]), false);
        assertEq(factory.isValidFacet(facets[1]), false);
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
        Controller controller = Controller(payable(factory.deploy(admin)));

        AccessControls accessControls = AccessControls(controller.accessControls());
        ALMProxy       almProxy       = ALMProxy(payable(controller.proxy()));
        RateLimits     rateLimits     = RateLimits(controller.rateLimits());

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
