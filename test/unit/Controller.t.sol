// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IController } from "../../src/interfaces/IController.sol";

import { Controller } from "../../src/Controller.sol";

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

    constructor(address accessControls_, address parameters_, address proxy_, address rateLimits_)
        Controller(accessControls_, parameters_, proxy_, rateLimits_) {}

    function accessControls() public view returns (address) {
        return _getControllerStorage().accessControls;
    }

    function parameters() public view returns (address) {
        return _getControllerStorage().parameters;
    }

    function proxy() public view returns (address) {
        return _getControllerStorage().proxy;
    }

    function rateLimits() public view returns (address) {
        return _getControllerStorage().rateLimits;
    }

}

contract Controller_Tests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal accessControls = makeAddr("accessControls");
    address internal parameters     = makeAddr("parameters");
    address internal proxy          = makeAddr("proxy");
    address internal rateLimits     = makeAddr("rateLimits");

    address internal admin        = makeAddr("admin");
    address internal unauthorized = makeAddr("unauthorized");

    ControllerHarness internal controller;

    function setUp() external {
        controller = new ControllerHarness(accessControls, parameters, proxy, rateLimits);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor() external {
        assertEq(controller.accessControls(), accessControls);
        assertEq(controller.parameters(),     parameters);
        assertEq(controller.proxy(),          proxy);
        assertEq(controller.rateLimits(),     rateLimits);
    }

    /**********************************************************************************************/
    /*** setFacet Tests                                                                         ***/
    /**********************************************************************************************/

    function test_setFacet_notAdmin() external {
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
        controller.setFacet(bytes4(0), address(0), bytes4(0));
    }

    function test_setFacet() external {
        bytes4  callSelector     = bytes4(0x12345678);
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = bytes4(0x87654321);

        _expectAndMockCall(
            accessControls,
            0,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector,
                DEFAULT_ADMIN_ROLE,
                admin
            ),
            abi.encode(true)
        );

        _expectAndMockCall(
            parameters,
            0,
            abi.encodeWithSignature(
                "set(string,bytes32)",
                "sky.pau.controller.facet.0x12345678",
                0x0000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd87654321
            ),
            ""
        );

        vm.expectEmit(address(controller));
        emit IController.FacetSet(callSelector, facet, delegateSelector);

        vm.prank(admin);
        controller.setFacet(callSelector, facet, delegateSelector);
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

    function test_fallback_facetNotFound() external {
        vm.mockCall(
            parameters,
            abi.encodeWithSignature(
                "get(string)",
                "sky.pau.controller.facet.0xe4343b69" // IMockController.facetFoo.selector
            ),
            abi.encode(0x0000000000000000000000000000000000000000000000000000000000000000)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IController.FacetNotFound.selector, IMockController.facetFoo.selector)
        );

        IMockController(address(controller)).facetFoo();
    }

    function test_fallback_facetRevert() external {
        vm.mockCall(
            parameters,
            abi.encodeWithSignature(
                "get(string)",
                "sky.pau.controller.facet.0xe4343b69" // IMockController.facetFoo.selector
            ),
            abi.encode(0x0000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcdc2985578) // facet . IMockFacet.foo.selector
        );

        bytes memory revertData = abi.encodeWithSelector(IMockFacet.MockError.selector, 111222);

        vm.mockCallRevert(
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, // facet
            abi.encodeWithSelector(bytes4(0xc2985578)), // IMockFacet.foo.selector
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

        _expectAndMockCall(
            parameters,
            0,
            abi.encodeWithSignature(
                "get(string)",
                "sky.pau.controller.facet.0xe7902b4c" // IMockController.facetBar.selector
            ),
            abi.encode(0x0000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcdc88a4d25) // facet . IMockFacet.bar.selector
        );

        _expectAndMockCall(
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, // facet
            abi.encodeWithSelector(
                bytes4(0xc88a4d25), // IMockFacet.bar.selector
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

    function _expectAndMockCall(
        address        callee,
        bytes   memory data,
        bytes   memory returnData
    ) internal {
        vm.expectCall(callee, data);
        vm.mockCall(callee, data, returnData);
    }

    function _expectAndMockCall(
        address        callee,
        uint256        msgValue,
        bytes   memory data,
        bytes   memory returnData
    ) internal {
        vm.expectCall(callee, msgValue, data);
        vm.mockCall(callee, msgValue, data, returnData);
    }

}
