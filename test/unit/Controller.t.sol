// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IController } from "../../src/interfaces/IController.sol";

import { Controller } from "../../src/Controller.sol";

import { MockPAUFactory } from "../mocks/Mocks.sol";

interface IMockFacet {

    error MockError(uint256 arg);

    function foo() external;

    function bar(
        address           arg0,
        bool[]     memory arg1,
        bytes32           arg2,
        int256[][] memory arg3,
        uint256           arg4,
        bytes      memory arg5,
        string[]   memory arg6
    )
        external
        returns (
            string[]   memory,
            bytes      memory,
            uint256,
            int256[][] memory,
            bytes32,
            bool[]     memory,
            address
        );

}

interface IMockController {

    function facetFoo() external;

    function facetBar(
        address           arg0,
        bool[]     memory arg1,
        bytes32           arg2,
        int256[][] memory arg3,
        uint256           arg4,
        bytes      memory arg5,
        string[]   memory arg6
    )
        external
        returns (
            string[]   memory,
            bytes      memory,
            uint256,
            int256[][] memory,
            bytes32,
            bool[]     memory,
            address
        );

}

contract ControllerHarness is Controller {

    constructor(address accessControls_, address proxy_, address rateLimits_, address factory_)
        Controller(accessControls_, proxy_, rateLimits_, factory_) {}
    
    function __setDispatch(bytes4 callSelector, address facet, bytes4 delegateSelector) external {
        _getControllerStorage().dispatches[callSelector] = Dispatch(facet, delegateSelector);
    }

    function __getDispatchFacet(bytes4 callSelector) external view returns (address) {
        return _getControllerStorage().dispatches[callSelector].facet;
    }

    function __getDispatchSelector(bytes4 callSelector) external view returns (bytes4) {
        return _getControllerStorage().dispatches[callSelector].delegateSelector;
    }

}

contract Controller_Tests is Test {

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal accessControls = makeAddr("accessControls");
    address internal proxy          = makeAddr("proxy");
    address internal rateLimits     = makeAddr("rateLimits");

    address internal admin        = makeAddr("admin");
    address internal unauthorized = makeAddr("unauthorized");

    ControllerHarness internal controller;
    MockPAUFactory    internal factory;

    function setUp() external {
        factory    = new MockPAUFactory();
        controller = new ControllerHarness(accessControls, proxy, rateLimits, address(factory));
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor() external {
        assertEq(controller.accessControls(), accessControls);
        assertEq(controller.proxy(),          proxy);
        assertEq(controller.rateLimits(),     rateLimits);
    }

    /**********************************************************************************************/
    /*** setDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_setDispatch_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        controller.setDispatch(bytes4(0), address(0), bytes4(0));
    }

    function test_setDispatch_notAdmin() external {
        vm.mockCall(
            accessControls,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector,
                DEFAULT_ADMIN_ROLE,
                unauthorized
            ),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.setDispatch(bytes4(0), address(0), bytes4(0));
    }

    function test_setDispatch() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        _expectAndMockCall(
            accessControls,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector,
                DEFAULT_ADMIN_ROLE,
                admin
            ),
            abi.encode(true)
        );

        vm.expectEmit(address(controller));
        emit IController.DispatchSet(callSelector, facet, delegateSelector);

        vm.prank(admin);
        controller.setDispatch(callSelector, facet, delegateSelector);

        assertEq(controller.__getDispatchFacet(callSelector),    facet);
        assertEq(controller.__getDispatchSelector(callSelector), delegateSelector);
    }

    /**********************************************************************************************/
    /*** getDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_getDispatch() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        controller.__setDispatch(callSelector, facet, delegateSelector);

        ( address returnedFacet, bytes4 returnedDelegateSelector ) = controller.getDispatch(callSelector);

        assertEq(returnedFacet,            facet);
        assertEq(returnedDelegateSelector, delegateSelector);
    }

    /**********************************************************************************************/
    /*** receive Tests                                                                          ***/
    /**********************************************************************************************/

    function test_receive() external {
        address account = makeAddr("account");

        deal(account, 1 ether);

        assertEq(account.balance,             1 ether);
        assertEq(address(controller).balance, 0);

        vm.prank(account);
        payable(controller).call{value: 1 ether}("");

        assertEq(account.balance,             0);
        assertEq(address(controller).balance, 1 ether);
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_dispatchNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(IController.DispatchNotFound.selector, IMockController.facetFoo.selector)
        );

        IMockController(address(controller)).facetFoo();
    }

    function test_fallback_facetRevert() external {
        address facet = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;

        controller.__setDispatch(IMockController.facetFoo.selector, facet, IMockFacet.foo.selector);

        bytes memory revertData = abi.encodeWithSelector(IMockFacet.MockError.selector, 111222);

        vm.mockCallRevert(
            facet,
            abi.encodeWithSelector(IMockFacet.foo.selector),
            revertData
        );

        vm.expectRevert(revertData);

        IMockController(address(controller)).facetFoo();
    }

    function test_fallback() external {
        deal(admin, 1 ether);

        address arg0 = makeAddr("arg0");

        bool[] memory arg1 = new bool[](3);
        arg1[0] = true;
        arg1[1] = false;
        arg1[2] = true;

        bytes32 arg2 = bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef);

        int256[][] memory arg3 = new int256[][](2);

        arg3[0] = new int256[](3);
        arg3[0][0] = 1;
        arg3[0][1] = -2;
        arg3[0][2] = 3;

        arg3[1] = new int256[](2);
        arg3[1][0] = -4;
        arg3[1][1] = 5;

        uint256 arg4 = 100;

        bytes memory arg5 = abi.encode("hello", "world");

        string[] memory arg6 = new string[](3);
        arg6[0] = "hello";
        arg6[1] = "world";
        arg6[2] = "foobar";

        controller.__setDispatch(
            IMockController.facetBar.selector,
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, // facet
            IMockFacet.bar.selector
        );

        _expectAndMockCall(
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, // facet
            abi.encodeWithSelector(
                IMockFacet.bar.selector,
                arg0,
                arg1,
                arg2,
                arg3,
                arg4,
                arg5,
                arg6
            ),
            abi.encode(arg6, arg5, arg4, arg3, arg2, arg1, arg0)
        );

        (
            string[]   memory resultA,
            bytes      memory resultB,
            uint256           resultC,
            int256[][] memory resultD,
            bytes32           resultE,
            bool[]     memory resultF,
            address           resultG
        ) = IMockController(address(controller)).facetBar(
            arg0,
            arg1,
            arg2,
            arg3,
            arg4,
            arg5,
            arg6
        );

        assertEq(resultA.length, arg6.length);

        for (uint256 i; i < arg6.length; ++i) {
            assertEq(resultA[i], arg6[i]);
        }

        assertEq(keccak256(resultB), keccak256(arg5));

        assertEq(resultC, arg4);

        assertEq(resultD.length, arg3.length);

        for (uint256 i; i < arg3.length; ++i) {

            assertEq(resultD[i].length, arg3[i].length);

            for (uint256 j; j < arg3[i].length; ++j) {
                assertEq(resultD[i][j], arg3[i][j]);
            }
        }

        assertEq(resultE, arg2);

        assertEq(resultF.length, arg1.length);

        for (uint256 i; i < arg1.length; ++i) {
            assertEq(resultF[i], arg1[i]);
        }

        assertEq(resultG, arg0);
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _expectAndMockCall(address callee, bytes memory data, bytes memory returnData) internal {
        vm.expectCall(callee, data);
        vm.mockCall(callee, data, returnData);
    }

}
