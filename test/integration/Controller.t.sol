// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import { IController } from "../../src/interfaces/IController.sol";

import { ControllerTestBase } from "./ControllerTestBase.t.sol";

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

contract ControllerIntegration_Tests is ControllerTestBase {

    IController internal controller;

    function setUp() public override {
        super.setUp();

        controller = IController(controllerAddress);
    }

    /**********************************************************************************************/
    /*** setDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_setDispatch_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.setDispatch(bytes4(0), address(0), bytes4(0));
    }

    function test_setDispatch() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        vm.expectEmit(address(controller));
        emit IController.DispatchSet(callSelector, facet, delegateSelector);

        vm.prank(admin);
        controller.setDispatch(callSelector, facet, delegateSelector);

        ( address returnedFacet, bytes4 returnedDelegateSelector ) = controller.getDispatch(callSelector);

        assertEq(returnedFacet,            facet);
        assertEq(returnedDelegateSelector, delegateSelector);

        vm.expectEmit(address(controller));
        emit IController.DispatchSet(callSelector, address(0), bytes4(0));

        vm.prank(admin);
        controller.setDispatch(callSelector, address(0), bytes4(0));

        ( returnedFacet, returnedDelegateSelector ) = controller.getDispatch(callSelector);

        assertEq(returnedFacet,            address(0));
        assertEq(returnedDelegateSelector, bytes4(0));
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_facetNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IController.DispatchNotFound.selector,
                IMockController.foo.selector
            )
        );

        IMockController(address(controller)).foo(10);

        address facet1 = address(new MockFacet1());
        address facet2 = address(new MockFacet2());

        vm.prank(admin);
        controller.setDispatch(IMockController.foo.selector, facet1, MockFacet1.divide.selector);

        assertEq(IMockController(address(controller)).foo(12), 6);

        vm.prank(admin);
        controller.setDispatch(IMockController.foo.selector, facet1, MockFacet1.multiply.selector);

        assertEq(IMockController(address(controller)).foo(12), 24);

        vm.prank(admin);
        controller.setDispatch(IMockController.foo.selector, facet2, MockFacet2.multiply.selector);

        assertEq(IMockController(address(controller)).foo(12), 48);

        vm.prank(admin);
        controller.setDispatch(IMockController.foo.selector, facet2, MockFacet2.divide.selector);

        assertEq(IMockController(address(controller)).foo(12), 3);

        vm.prank(admin);
        controller.setDispatch(IMockController.foo.selector, address(0), bytes4(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.DispatchNotFound.selector,
                IMockController.foo.selector
            )
        );

        IMockController(address(controller)).foo(10);
    }
}
