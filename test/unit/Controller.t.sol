// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IController }             from "../../src/interfaces/IController.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";

import { Controller } from "../../src/Controller.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract ControllerHarness is Controller {

    constructor(address accessControls_, address beacon_, address proxy_, address rateLimits_)
        Controller(accessControls_, beacon_, proxy_, rateLimits_)
    {}

    function __setDispatch(bytes4 callSelector, IEnumerableIntegrations.Dispatch memory dispatch) external {
        _getControllerStorage().dispatches[callSelector] = dispatch;
    }

}

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

    function facetFoo() external payable;

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

contract Controller_Tests is UnitTestBase {

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant REENTRANCY_GUARD_SLOT        = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    bytes32 internal constant REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));

    address internal accessControls = makeAddr("accessControls");
    address internal beacon         = makeAddr("beacon");
    address internal proxy          = makeAddr("proxy");
    address internal rateLimits     = makeAddr("rateLimits");

    ControllerHarness internal controller;

    function setUp() external {
        controller = new ControllerHarness(accessControls, beacon, proxy, rateLimits);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAccessControls() external {
        vm.expectRevert(IController.ZeroAccessControls.selector);
        new Controller(address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroBeacon() external {
        vm.expectRevert(IController.ZeroBeacon.selector);
        new Controller(accessControls, address(0), address(0), address(0));
    }

    function test_constructor_zeroProxy() external {
        vm.expectRevert(IController.ZeroProxy.selector);
        new Controller(accessControls, beacon, address(0), address(0));
    }

    function test_constructor_zeroRateLimits() external {
        vm.expectRevert(IController.ZeroRateLimits.selector);
        new Controller(accessControls, beacon, proxy, address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Tests                                                                    ***/
    /**********************************************************************************************/

    function test_initialState() external {
        assertEq(controller.accessControls(), accessControls);
        assertEq(controller.beacon(),         beacon);
        assertEq(controller.proxy(),          proxy);
        assertEq(controller.rateLimits(),     rateLimits);

        assertEq(vm.load(address(controller), REENTRANCY_GUARD_SLOT), REENTRANCY_GUARD_NOT_ENTERED);
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_invalidCallDataLengthBoundary() external {
        vm.expectRevert(abi.encodeWithSelector(IController.InvalidCallDataLength.selector, 3));
        address(controller).call(hex"123456");

        // Expect revert with CallSelectorNotWired error, but not with InvalidCallDataLength.
        vm.expectRevert(
            abi.encodeWithSelector(IController.CallSelectorNotWired.selector, bytes4(hex"12345678"))
        );
        address(controller).call(hex"12345678");
    }

    function test_fallback_callSelectorNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.facetFoo.selector)
        );

        IMockController(address(controller)).facetFoo();
    }

    function test_fallback_facetRevert() external {
        address facet = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;

        controller.__setDispatch(
            IMockController.facetFoo.selector,
            IEnumerableIntegrations.Dispatch(facet, IMockFacet.foo.selector)
        );

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
            IEnumerableIntegrations.Dispatch(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, IMockFacet.bar.selector)
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

    function test_fallback_zeroSelectors() external {
        controller.__setDispatch(
            bytes4(0x00000000),
            IEnumerableIntegrations.Dispatch(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, bytes4(0x00000000))
        );

        _expectAndMockCall(
            0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD,
            abi.encodeWithSelector(bytes4(0x00000000)),
            abi.encode(uint256(42))
        );

        ( bool success, bytes memory returnData ) = address(controller).call(abi.encodeWithSelector(bytes4(0x00000000)));

        assertEq(success,                           true);
        assertEq(abi.decode(returnData, (uint256)), 42);
    }

    function test_fallback_withValue() external {
        address account = makeAddr("account");

        deal(account, 1 ether);

        controller.__setDispatch(
            IMockController.facetFoo.selector,
            IEnumerableIntegrations.Dispatch(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, IMockFacet.foo.selector)
        );

        assertEq(account.balance,             1 ether);
        assertEq(address(controller).balance, 0);

        // NOTE: There seems to be a bug in `expectCall` for delegate calls where the value cannot be checked.
        vm.expectCall(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, abi.encodeWithSelector(IMockFacet.foo.selector));
        vm.mockCall(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD, 1 ether, abi.encodeWithSelector(IMockFacet.foo.selector), '');

        vm.prank(account);
        IMockController(address(controller)).facetFoo{value: 1 ether}();

        assertEq(account.balance,             0);
        assertEq(address(controller).balance, 1 ether);
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _expectAndMockCall(address callee, bytes memory data, bytes memory returnData) internal {
        vm.expectCall(callee, data);
        vm.mockCall(callee, data, returnData);
    }

}
