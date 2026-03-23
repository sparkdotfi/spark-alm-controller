// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IController } from "../../src/interfaces/IController.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { Controller }     from "../../src/Controller.sol";
import { Parameters }     from "../../src/Parameters.sol";

contract MockFacet1 {

    function divide(uint256 arg) external pure returns (uint256) {
        return arg / 2;
    }

    function multiply(uint256 arg) external pure returns (uint256) {
        return arg * 2;
    }

}

contract MockFacet2 {

    function divide(uint256 arg) external pure returns (uint256) {
        return arg / 4;
    }

    function multiply(uint256 arg) external pure returns (uint256) {
        return arg * 4;
    }

}

interface IMockController {

    function foo(uint256 arg) external pure returns (uint256);

}

contract ControllerIntegration_Tests is Test {

    AccessControls internal accessControls;
    Controller     internal controller;
    Parameters     internal parameters;

    address internal admin        = makeAddr("admin");
    address internal proxy        = makeAddr("proxy");
    address internal rateLimits   = makeAddr("rateLimits");
    address internal unauthorized = makeAddr("unauthorized");

    function setUp() external {
        accessControls = new AccessControls(admin);
        parameters     = new Parameters(admin);
        controller     = new Controller(address(accessControls), address(parameters), proxy, rateLimits);

        vm.startPrank(admin);
        parameters.grantRole(parameters.CONTROLLER_ROLE(), address(controller));
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** setFacet Tests                                                                         ***/
    /**********************************************************************************************/

    function test_setFacet_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.setFacet(bytes4(0), address(0), bytes4(0));
    }

    function test_setFacet() external {
        bytes4  callSelector     = bytes4(0x12345678);
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = bytes4(0x87654321);

        vm.expectEmit(address(controller));
        emit IController.FacetSet(callSelector, facet, delegateSelector);

        vm.prank(admin);
        controller.setFacet(callSelector, facet, delegateSelector);

        assertEq(
            parameters.get("sky.pau.controller.facet.0x12345678"),
            0x0000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd87654321
        );

        vm.expectEmit(address(controller));
        emit IController.FacetSet(callSelector, address(0), bytes4(0));

        vm.prank(admin);
        controller.setFacet(callSelector, address(0), bytes4(0));

        assertEq(parameters.get("sky.pau.controller.facet.0x12345678"), bytes32(0));
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_facetNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IController.FacetNotFound.selector,
                IMockController.foo.selector
            )
        );

        IMockController(address(controller)).foo(10);

        address facet1 = address(new MockFacet1());
        address facet2 = address(new MockFacet2());

        vm.prank(admin);
        controller.setFacet(IMockController.foo.selector, facet1, MockFacet1.divide.selector);

        assertEq(IMockController(address(controller)).foo(12), 6);

        vm.prank(admin);
        controller.setFacet(IMockController.foo.selector, facet1, MockFacet1.multiply.selector);

        assertEq(IMockController(address(controller)).foo(12), 24);

        vm.prank(admin);
        controller.setFacet(IMockController.foo.selector, facet2, MockFacet2.multiply.selector);

        assertEq(IMockController(address(controller)).foo(12), 48);

        vm.prank(admin);
        controller.setFacet(IMockController.foo.selector, facet2, MockFacet2.divide.selector);

        assertEq(IMockController(address(controller)).foo(12), 3);

        vm.prank(admin);
        controller.setFacet(IMockController.foo.selector, address(0), bytes4(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.FacetNotFound.selector,
                IMockController.foo.selector
            )
        );

        IMockController(address(controller)).foo(10);
    }
}
