// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { EnumerableSet }   from "../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IController } from "../../src/interfaces/IController.sol";
import { IPAUFactory } from "../../src/interfaces/IPAUFactory.sol";

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

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    constructor(address accessControls_, address factory_, address proxy_, address rateLimits_)
        Controller(accessControls_, factory_, proxy_, rateLimits_) {}

    function __addFacet(address facet) external {
        _getControllerStorage().facets.add(facet);
    }

    function __removeFacet(address facet) external {
        _getControllerStorage().facets.remove(facet);
    }

    function __setDispatch(bytes4 callSelector, address facet, bytes4 delegateSelector) external {
        _getControllerStorage().dispatches[callSelector] = Dispatch(facet, delegateSelector);
    }

    function __addWire(address facet, bytes4 callSelector, bytes4 delegateSelector) external {
        _getControllerStorage().wiring[facet].add(_toWiring(callSelector, delegateSelector));
    }

    function __removeWire(address facet, bytes4 callSelector, bytes4 delegateSelector) external {
        _getControllerStorage().wiring[facet].remove(_toWiring(callSelector, delegateSelector));
    }

    function __getHasFacet(address facet) external view returns (bool) {
        return _getControllerStorage().facets.contains(facet);
    }

    function __getDispatchFacet(bytes4 callSelector) external view returns (address) {
        return _getControllerStorage().dispatches[callSelector].facet;
    }

    function __getDispatchSelector(bytes4 callSelector) external view returns (bytes4) {
        return _getControllerStorage().dispatches[callSelector].delegateSelector;
    }

    function __getHasWiring(address facet, bytes4 callSelector, bytes4 delegateSelector) external view returns (bool) {
        return _getControllerStorage().wiring[facet].contains(_toWiring(callSelector, delegateSelector));
    }

}

contract Controller_Tests is Test {

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal accessControls = makeAddr("accessControls");
    address internal factory        = makeAddr("factory");
    address internal proxy          = makeAddr("proxy");
    address internal rateLimits     = makeAddr("rateLimits");

    address internal admin        = makeAddr("admin");
    address internal unauthorized = makeAddr("unauthorized");

    ControllerHarness internal controller;

    function setUp() external {
        controller = new ControllerHarness(accessControls, factory, proxy, rateLimits);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAccessControls() external {
        vm.expectRevert(IController.ZeroAccessControls.selector);
        new Controller({
            accessControls_ : address(0),
            factory_        : address(0),
            proxy_          : address(0),
            rateLimits_     : address(0)
        });
    }

    function test_constructor_zeroFactory() external {
        vm.expectRevert(IController.ZeroFactory.selector);
        new Controller({
            accessControls_ : accessControls,
            factory_        : address(0),
            proxy_          : address(0),
            rateLimits_     : address(0)
        });
    }

    function test_constructor_zeroProxy() external {
        vm.expectRevert(IController.ZeroProxy.selector);
        new Controller({
            accessControls_ : accessControls,
            factory_        : factory,
            proxy_          : address(0),
            rateLimits_     : address(0)
        });
    }

    function test_constructor_zeroRateLimits() external {
        vm.expectRevert(IController.ZeroRateLimits.selector);
        new Controller({
            accessControls_ : accessControls,
            factory_        : factory,
            proxy_          : proxy,
            rateLimits_     : address(0)
        });
    }

    function test_constructor() external {
        Controller controller = new Controller({
            accessControls_ : accessControls,
            factory_        : factory,
            proxy_          : proxy,
            rateLimits_     : rateLimits
        });

        assertEq(controller.accessControls(), accessControls);
        assertEq(controller.factory(),        factory);
        assertEq(controller.proxy(),          proxy);
        assertEq(controller.rateLimits(),     rateLimits);
    }

    /**********************************************************************************************/
    /*** addWire Tests                                                                          ***/
    /**********************************************************************************************/

    function test_addWire_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.addWire(address(0), IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire_notAdmin() external {
        _expectAndMockAccessControlCall(unauthorized, false);

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.addWire(address(0), IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire_zeroFacet() external {
        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(IController.ZeroFacet.selector);
        vm.prank(admin);
        controller.addWire(address(0), IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire_invalidFacet() external {
        address facet = makeAddr("facet");

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       false);

        vm.expectRevert(abi.encodeWithSelector(IController.InvalidFacet.selector, facet));
        vm.prank(admin);
        controller.addWire(facet, IController.Wire(bytes4(0), bytes4(0)));
    }

    function test_addWire_callSelectorHardcoded() external {
        address facet = makeAddr("facet");

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.addWire.selector
            )
        );

        vm.prank(admin);
        controller.addWire(facet, IController.Wire(IController.addWire.selector, bytes4(0)));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.factory.selector
            )
        );

        vm.prank(admin);
        controller.addWire(facet, IController.Wire(IController.factory.selector, bytes4(0)));
    }

    function test_addWire_callSelectorHardcoded_exhaustive() external {
        address facet = makeAddr("facet");

        bytes4[] memory callSelectors = new bytes4[](14);
        callSelectors[0]  = IController.addWire.selector;
        callSelectors[1]  = IController.addWires.selector;
        callSelectors[2]  = IController.removeWire.selector;
        callSelectors[3]  = IController.removeAllWiresFor.selector;
        callSelectors[4]  = IController.removeWires.selector;
        callSelectors[5]  = IController.accessControls.selector;
        callSelectors[6]  = IController.circuits.selector;
        callSelectors[7]  = IController.factory.selector;
        callSelectors[8]  = IController.proxy.selector;
        callSelectors[9]  = IController.rateLimits.selector;
        callSelectors[10] = IController.getDispatch.selector;
        callSelectors[11] = IController.getDispatches.selector;
        callSelectors[12] = IController.getWiring.selector;
        callSelectors[13] = IController.getWirings.selector;

        for (uint256 i = 0; i < callSelectors.length; ++i) {
            _expectAndMockAccessControlCall(admin, true);
            _expectAndMockFactoryCall(facet,       true);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IController.CallSelectorHardcoded.selector,
                    callSelectors[i]
                )
            );

            vm.prank(admin);
            controller.addWire(facet, IController.Wire(callSelectors[i], bytes4(0)));
        }
    }

    function test_addWire_callSelectorAlreadyWired() external {
        address facet        = makeAddr("facet");
        bytes4  callSelector = 0x12345678;

        controller.__setDispatch(callSelector, facet, bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorAlreadyWired.selector, callSelector));
        vm.prank(admin);
        controller.addWire(facet, IController.Wire(callSelector, bytes4(0)));
    }

    function test_addWire() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(callSelector),    address(0));
        assertEq(controller.__getDispatchSelector(callSelector), bytes4(0));

        assertEq(controller.__getHasWiring(facet, callSelector, delegateSelector), false);

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectEmit(address(controller));
        emit IController.WireAdded({
            callSelector     : callSelector,
            delegateSelector : delegateSelector,
            facet            : facet
        });

        vm.prank(admin);
        controller.addWire(facet, IController.Wire(callSelector, delegateSelector));

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(callSelector),    facet);
        assertEq(controller.__getDispatchSelector(callSelector), delegateSelector);

        assertEq(controller.__getHasWiring(facet, callSelector, delegateSelector), true);
    }

    /**********************************************************************************************/
    /*** addWires Tests                                                                         ***/
    /**********************************************************************************************/

    function test_addWires_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.addWires(address(0), new IController.Wire[](0));
    }

    function test_addWires_notAdmin() external {
        _expectAndMockAccessControlCall(unauthorized, false);

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.addWires(address(0), new IController.Wire[](0));
    }

    function test_addWires_emptyArray() external {
        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(IController.EmptyArray.selector);
        vm.prank(admin);
        controller.addWires(address(0), new IController.Wire[](0));
    }

    function test_addWires_zeroFacet() external {
        IController.Wire[] memory wires = new IController.Wire[](2);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(IController.ZeroFacet.selector);
        vm.prank(admin);
        controller.addWires(address(0), wires);
    }

    function test_addWires_invalidFacet() external {
        address facet = makeAddr("facet");

        IController.Wire[] memory wires = new IController.Wire[](2);
        wires[0] = IController.Wire(0x12345678, bytes4(0));
        wires[1] = IController.Wire(0x87654321, bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       false);

        vm.expectRevert(abi.encodeWithSelector(IController.InvalidFacet.selector, facet));
        vm.prank(admin);
        controller.addWires(facet, wires);
    }

    function test_addWires_callSelectorHardcoded() external {
        address facet = makeAddr("facet");

        IController.Wire[] memory wires = new IController.Wire[](2);
        wires[0] = IController.Wire(IController.addWires.selector, bytes4(0));
        wires[1] = IController.Wire(0x12456789,                    bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.addWires.selector
            )
        );

        vm.prank(admin);
        controller.addWires(facet, wires);

        wires[0] = IController.Wire(0x12345678,                   bytes4(0));
        wires[1] = IController.Wire(IController.factory.selector, bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.factory.selector
            )
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
    }

    function test_addWires_callSelectorAlreadyWired() external {
        address facet        = makeAddr("facet");
        bytes4  callSelector = 0x12345678;

        controller.__setDispatch(callSelector, facet, bytes4(0));

        IController.Wire[] memory wires = new IController.Wire[](2);
        wires[0] = IController.Wire(callSelector, bytes4(0));
        wires[1] = IController.Wire(0x87654321,   bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorAlreadyWired.selector, callSelector));
        vm.prank(admin);
        controller.addWires(facet, wires);

        wires[0] = IController.Wire(0x87654321,   bytes4(0));
        wires[1] = IController.Wire(callSelector, bytes4(0));

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorAlreadyWired.selector, callSelector));
        vm.prank(admin);
        controller.addWires(facet, wires);
    }

    function test_addWires() external {
        address facet = makeAddr("facet");

        IController.Wire[] memory wires = new IController.Wire[](2);
        wires[0] = IController.Wire(0x12345678, 0x87654321);
        wires[1] = IController.Wire(0xFEDCBA98, 0x89ABCDEF);

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(wires[0].callSelector),    address(0));
        assertEq(controller.__getDispatchSelector(wires[0].callSelector), bytes4(0));

        assertEq(controller.__getDispatchFacet(wires[1].callSelector),    address(0));
        assertEq(controller.__getDispatchSelector(wires[1].callSelector), bytes4(0));

        assertEq(controller.__getHasWiring(facet, wires[0].callSelector, wires[0].delegateSelector), false);
        assertEq(controller.__getHasWiring(facet, wires[1].callSelector, wires[1].delegateSelector), false);

        _expectAndMockAccessControlCall(admin, true);
        _expectAndMockFactoryCall(facet,       true);

        vm.expectEmit(address(controller));
        emit IController.WireAdded({
            callSelector     : 0x12345678,
            delegateSelector : 0x87654321,
            facet            : makeAddr("facet")
        });

        vm.expectEmit(address(controller));
        emit IController.WireAdded({
            callSelector     : 0xFEDCBA98,
            delegateSelector : 0x89ABCDEF,
            facet            : makeAddr("facet")
        });

        vm.prank(admin);
        controller.addWires(facet, wires);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(wires[0].callSelector),    facet);
        assertEq(controller.__getDispatchSelector(wires[0].callSelector), wires[0].delegateSelector);

        assertEq(controller.__getDispatchFacet(wires[1].callSelector),    facet);
        assertEq(controller.__getDispatchSelector(wires[1].callSelector), wires[1].delegateSelector);

        assertEq(controller.__getHasWiring(facet, wires[0].callSelector, wires[0].delegateSelector), true);
        assertEq(controller.__getHasWiring(facet, wires[1].callSelector, wires[1].delegateSelector), true);
    }

    /**********************************************************************************************/
    /*** removeWire Tests                                                                       ***/
    /**********************************************************************************************/

    function test_removeWire_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeWire(bytes4(0));
    }

    function test_removeWire_notAdmin() external {
        _expectAndMockAccessControlCall(unauthorized, false);

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeWire(bytes4(0));
    }

    function test_removeWire_callSelectorIsHardcoded() external {
        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.addWire.selector
            )
        );

        vm.prank(admin);
        controller.removeWire(IController.addWire.selector);
    }

    function test_removeWire_callSelectorNotWired() external {
        bytes4 callSelector = 0x12456789;

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, callSelector));
        vm.prank(admin);
        controller.removeWire(callSelector);
    }

    function test_removeWire() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        controller.__addFacet(facet);

        controller.__setDispatch(callSelector, facet, delegateSelector);

        controller.__addWire(facet, callSelector, delegateSelector);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(callSelector),    facet);
        assertEq(controller.__getDispatchSelector(callSelector), delegateSelector);

        assertEq(controller.__getHasWiring(facet, callSelector, delegateSelector), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector: callSelector });

        vm.prank(admin);
        controller.removeWire(callSelector);

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(callSelector),    address(0));
        assertEq(controller.__getDispatchSelector(callSelector), bytes4(0));

        assertEq(controller.__getHasWiring(facet, callSelector, delegateSelector), false);
    }

    function test_removeWire_oneThenLast() external {
        address facet = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;

        bytes4[] memory delegateSelectors = new bytes4[](2);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;

        controller.__addFacet(facet);

        controller.__setDispatch(callSelectors[0], facet, delegateSelectors[0]);
        controller.__setDispatch(callSelectors[1], facet, delegateSelectors[1]);

        controller.__addWire(facet, callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facet, callSelectors[1], delegateSelectors[1]);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[0]), delegateSelectors[0]);
        assertEq(controller.__getDispatchFacet(callSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[1]), delegateSelectors[1]);

        assertEq(controller.__getHasWiring(facet, callSelectors[0], delegateSelectors[0]), true);
        assertEq(controller.__getHasWiring(facet, callSelectors[1], delegateSelectors[1]), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[0] });

        vm.prank(admin);
        controller.removeWire(callSelectors[0]);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[0]), bytes4(0));
        assertEq(controller.__getDispatchFacet(callSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[1]), delegateSelectors[1]);

        assertEq(controller.__getHasWiring(facet, callSelectors[0], delegateSelectors[0]), false);
        assertEq(controller.__getHasWiring(facet, callSelectors[1], delegateSelectors[1]), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[1] });

        vm.prank(admin);
        controller.removeWire(callSelectors[1]);

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[0]), bytes4(0));
        assertEq(controller.__getDispatchFacet(callSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[1]), bytes4(0));

        assertEq(controller.__getHasWiring(facet, callSelectors[0], delegateSelectors[0]), false);
        assertEq(controller.__getHasWiring(facet, callSelectors[1], delegateSelectors[1]), false);
    }

    /**********************************************************************************************/
    /*** removeWires Tests                                                                      ***/
    /**********************************************************************************************/

    function test_removeWires_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeWires(new bytes4[](0));
    }

    function test_removeWires_notAdmin() external {
        _expectAndMockAccessControlCall(unauthorized, false);

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeWires(new bytes4[](0));
    }

    function test_removeWires_emptyArray() external {
        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(IController.EmptyArray.selector);
        vm.prank(admin);
        controller.removeWires(new bytes4[](0));
    }

    function test_removeWires_callSelectorHardcoded() external {
        controller.__setDispatch(0x12456789, makeAddr("facet"), bytes4(0));

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = IController.addWires.selector;
        callSelectors[1] = 0x12456789;

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.addWires.selector
            )
        );

        vm.prank(admin);
        controller.removeWires(callSelectors);

        callSelectors[0] = 0x12456789;
        callSelectors[1] = IController.factory.selector;

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IController.CallSelectorHardcoded.selector,
                IController.factory.selector
            )
        );

        vm.prank(admin);
        controller.removeWires(callSelectors);
    }

    function test_removeWires_callSelectorNotWired() external {
        bytes4 callSelector = 0x12345678;

        controller.__setDispatch(0x87654321, makeAddr("facet"), bytes4(0));

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = callSelector;
        callSelectors[1] = 0x87654321;

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, callSelector));
        vm.prank(admin);
        controller.removeWires(callSelectors);

        callSelectors[0] = 0x87654321;
        callSelectors[1] = callSelector;

        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, callSelector));
        vm.prank(admin);
        controller.removeWires(callSelectors);
    }

    function test_removeWires() external {
        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;

        address[] memory facets = new address[](2);
        facets[0] = makeAddr("facet1");
        facets[1] = makeAddr("facet2");

        bytes4[] memory delegateSelectors = new bytes4[](2);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;

        controller.__addFacet(facets[0]);
        controller.__addFacet(facets[1]);

        controller.__setDispatch(callSelectors[0], facets[0], delegateSelectors[0]);
        controller.__setDispatch(callSelectors[1], facets[1], delegateSelectors[1]);

        controller.__addWire(facets[0], callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facets[1], callSelectors[1], delegateSelectors[1]);

        assertEq(controller.__getHasFacet(facets[0]), true);
        assertEq(controller.__getHasFacet(facets[1]), true);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    facets[0]);
        assertEq(controller.__getDispatchSelector(callSelectors[0]), delegateSelectors[0]);

        assertEq(controller.__getDispatchFacet(callSelectors[1]),    facets[1]);
        assertEq(controller.__getDispatchSelector(callSelectors[1]), delegateSelectors[1]);

        assertEq(controller.__getHasWiring(facets[0], callSelectors[0], delegateSelectors[0]), true);
        assertEq(controller.__getHasWiring(facets[1], callSelectors[1], delegateSelectors[1]), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[0] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[1] });

        vm.prank(admin);
        controller.removeWires(callSelectors);

        assertEq(controller.__getHasFacet(facets[0]), false);
        assertEq(controller.__getHasFacet(facets[1]), false);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[0]), bytes4(0));

        assertEq(controller.__getDispatchFacet(callSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[1]), bytes4(0));

        assertEq(controller.__getHasWiring(facets[0], callSelectors[0], delegateSelectors[0]), false);
        assertEq(controller.__getHasWiring(facets[1], callSelectors[1], delegateSelectors[1]), false);
    }

    function test_removeWires_halfThenHalf() external {
        address facet = makeAddr("facet");

        bytes4[] memory firstHalfCallSelectors = new bytes4[](2);
        firstHalfCallSelectors[0] = 0x12345678;
        firstHalfCallSelectors[1] = 0x89ABCDEF;

        bytes4[] memory secondHalfCallSelectors = new bytes4[](2);
        secondHalfCallSelectors[0] = 0x11111111;
        secondHalfCallSelectors[1] = 0x22222222;

        bytes4[] memory firstHalfDelegateSelectors = new bytes4[](2);
        firstHalfDelegateSelectors[0] = 0x87654321;
        firstHalfDelegateSelectors[1] = 0xFECDAB98;

        bytes4[] memory secondHalfDelegateSelectors = new bytes4[](2);
        secondHalfDelegateSelectors[0] = 0x33333333;
        secondHalfDelegateSelectors[1] = 0x44444444;

        controller.__addFacet(facet);

        controller.__setDispatch(firstHalfCallSelectors[0],  facet, firstHalfDelegateSelectors[0]);
        controller.__setDispatch(firstHalfCallSelectors[1],  facet, firstHalfDelegateSelectors[1]);
        controller.__setDispatch(secondHalfCallSelectors[0], facet, secondHalfDelegateSelectors[0]);
        controller.__setDispatch(secondHalfCallSelectors[1], facet, secondHalfDelegateSelectors[1]);

        controller.__addWire(facet, firstHalfCallSelectors[0],  firstHalfDelegateSelectors[0]);
        controller.__addWire(facet, firstHalfCallSelectors[1],  firstHalfDelegateSelectors[1]);
        controller.__addWire(facet, secondHalfCallSelectors[0], secondHalfDelegateSelectors[0]);
        controller.__addWire(facet, secondHalfCallSelectors[1], secondHalfDelegateSelectors[1]);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[0]),    facet);
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[0]), firstHalfDelegateSelectors[0]);

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[1]), firstHalfDelegateSelectors[1]);

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[0]),    facet);
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[0]), secondHalfDelegateSelectors[0]);

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[1]), secondHalfDelegateSelectors[1]);

        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[0],  firstHalfDelegateSelectors[0]),  true);
        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[1],  firstHalfDelegateSelectors[1]),  true);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[0], secondHalfDelegateSelectors[0]), true);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[1], secondHalfDelegateSelectors[1]), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : firstHalfCallSelectors[0] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : firstHalfCallSelectors[1] });

        vm.prank(admin);
        controller.removeWires(firstHalfCallSelectors);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[0]), bytes4(0));

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[1]), bytes4(0));

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[0]),    facet);
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[0]), secondHalfDelegateSelectors[0]);

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[1]), secondHalfDelegateSelectors[1]);

        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[0],  firstHalfDelegateSelectors[0]),  false);
        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[1],  firstHalfDelegateSelectors[1]),  false);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[0], secondHalfDelegateSelectors[0]), true);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[1], secondHalfDelegateSelectors[1]), true);

        _expectAndMockAccessControlCall(admin, true);

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : secondHalfCallSelectors[0] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : secondHalfCallSelectors[1] });

        vm.prank(admin);
        controller.removeWires(secondHalfCallSelectors);

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[0]), bytes4(0));

        assertEq(controller.__getDispatchFacet(firstHalfCallSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(firstHalfCallSelectors[1]), bytes4(0));

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[0]), bytes4(0));

        assertEq(controller.__getDispatchFacet(secondHalfCallSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(secondHalfCallSelectors[1]), bytes4(0));

        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[0],  firstHalfDelegateSelectors[0]),  false);
        assertEq(controller.__getHasWiring(facet, firstHalfCallSelectors[1],  firstHalfDelegateSelectors[1]),  false);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[0], secondHalfDelegateSelectors[0]), false);
        assertEq(controller.__getHasWiring(facet, secondHalfCallSelectors[1], secondHalfDelegateSelectors[1]), false);
    }

    /**********************************************************************************************/
    /*** removeAllWiresFor Tests                                                                ***/
    /**********************************************************************************************/

    function test_removeAllWiresFor_reentrancy() external {
        vm.store(address(controller), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.removeAllWiresFor(address(0));
    }

    function test_removeAllWiresFor_notAdmin() external {
        _expectAndMockAccessControlCall(unauthorized, false);

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, unauthorized));
        vm.prank(unauthorized);
        controller.removeAllWiresFor(address(0));
    }

    function test_removeAllWiresFor_emptyArray() external {
        _expectAndMockAccessControlCall(admin, true);

        vm.expectRevert(IController.EmptyArray.selector);
        vm.prank(admin);
        controller.removeAllWiresFor(address(0));
    }

    function test_removeAllWiresFor() external {
        address facet = makeAddr("facet");

        bytes4[] memory callSelectors = new bytes4[](4);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;
        callSelectors[3] = 0x22222222;

        bytes4[] memory delegateSelectors = new bytes4[](4);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;
        delegateSelectors[3] = 0x44444444;

        controller.__addFacet(facet);

        controller.__setDispatch(callSelectors[0], facet, delegateSelectors[0]);
        controller.__setDispatch(callSelectors[1], facet, delegateSelectors[1]);
        controller.__setDispatch(callSelectors[2], facet, delegateSelectors[2]);
        controller.__setDispatch(callSelectors[3], facet, delegateSelectors[3]);

        controller.__addWire(facet, callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facet, callSelectors[1], delegateSelectors[1]);
        controller.__addWire(facet, callSelectors[2], delegateSelectors[2]);
        controller.__addWire(facet, callSelectors[3], delegateSelectors[3]);

        assertEq(controller.__getHasFacet(facet), true);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[0]), delegateSelectors[0]);

        assertEq(controller.__getDispatchFacet(callSelectors[1]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[1]), delegateSelectors[1]);

        assertEq(controller.__getDispatchFacet(callSelectors[2]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[2]), delegateSelectors[2]);

        assertEq(controller.__getDispatchFacet(callSelectors[3]),    facet);
        assertEq(controller.__getDispatchSelector(callSelectors[3]), delegateSelectors[3]);

        assertEq(controller.__getHasWiring(facet, callSelectors[0], delegateSelectors[0]), true);
        assertEq(controller.__getHasWiring(facet, callSelectors[1], delegateSelectors[1]), true);
        assertEq(controller.__getHasWiring(facet, callSelectors[2], delegateSelectors[2]), true);
        assertEq(controller.__getHasWiring(facet, callSelectors[3], delegateSelectors[3]), true);

        _expectAndMockAccessControlCall(admin, true);

        // NOTE: Ordering is 0 then reverse order of 1, 2, 3 due to how EnumerableSet inserts work.

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[0] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[3] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[2] });

        vm.expectEmit(address(controller));
        emit IController.WireRemoved({ callSelector : callSelectors[1] });

        vm.prank(admin);
        controller.removeAllWiresFor(facet);

        assertEq(controller.__getHasFacet(facet), false);

        assertEq(controller.__getDispatchFacet(callSelectors[0]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[0]), bytes4(0));

        assertEq(controller.__getDispatchFacet(callSelectors[1]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[1]), bytes4(0));

        assertEq(controller.__getDispatchFacet(callSelectors[2]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[2]), bytes4(0));

        assertEq(controller.__getDispatchFacet(callSelectors[3]),    address(0));
        assertEq(controller.__getDispatchSelector(callSelectors[3]), bytes4(0));

        assertEq(controller.__getHasWiring(facet, callSelectors[0], delegateSelectors[0]), false);
        assertEq(controller.__getHasWiring(facet, callSelectors[1], delegateSelectors[1]), false);
        assertEq(controller.__getHasWiring(facet, callSelectors[2], delegateSelectors[2]), false);
        assertEq(controller.__getHasWiring(facet, callSelectors[3], delegateSelectors[3]), false);
    }

    /**********************************************************************************************/
    /*** circuits Tests                                                                         ***/
    /**********************************************************************************************/

    function test_circuits() external {
        address[] memory facets = new address[](2);
        facets[0] = makeAddr("facet1");
        facets[1] = makeAddr("facet2");

        bytes4[] memory callSelectors = new bytes4[](3);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;

        bytes4[] memory delegateSelectors = new bytes4[](3);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;

        controller.__addFacet(facets[0]);
        controller.__addFacet(facets[1]);

        controller.__setDispatch(callSelectors[0], facets[0], delegateSelectors[0]);
        controller.__setDispatch(callSelectors[1], facets[1], delegateSelectors[1]);
        controller.__setDispatch(callSelectors[2], facets[1], delegateSelectors[2]);

        controller.__addWire(facets[0], callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facets[1], callSelectors[1], delegateSelectors[1]);
        controller.__addWire(facets[1], callSelectors[2], delegateSelectors[2]);

        IController.Circuit[] memory circuits = controller.circuits();

        assertEq(circuits.length, 2);

        assertEq(circuits[0].facet, facets[0]);

        assertEq(circuits[0].wires.length, 1);

        assertEq(circuits[0].wires[0].callSelector,     callSelectors[0]);
        assertEq(circuits[0].wires[0].delegateSelector, delegateSelectors[0]);

        assertEq(circuits[1].facet, facets[1]);

        assertEq(circuits[1].wires.length, 2);

        assertEq(circuits[1].wires[0].callSelector,     callSelectors[1]);
        assertEq(circuits[1].wires[0].delegateSelector, delegateSelectors[1]);
        assertEq(circuits[1].wires[1].callSelector,     callSelectors[2]);
        assertEq(circuits[1].wires[1].delegateSelector, delegateSelectors[2]);

    }

    /**********************************************************************************************/
    /*** getDispatch Tests                                                                      ***/
    /**********************************************************************************************/

    function test_getDispatch() external {
        bytes4  callSelector     = 0x12345678;
        address facet            = 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD;
        bytes4  delegateSelector = 0x87654321;

        controller.__setDispatch(callSelector, facet, delegateSelector);

        IController.Dispatch memory returnedDispatch = controller.getDispatch(callSelector);

        assertEq(returnedDispatch.facet,            facet);
        assertEq(returnedDispatch.delegateSelector, delegateSelector);
    }

    /**********************************************************************************************/
    /*** getDispatches Tests                                                                    ***/
    /**********************************************************************************************/

    function test_getDispatches() external {
        address[] memory facets = new address[](2);
        facets[0] = makeAddr("facet1");
        facets[1] = makeAddr("facet2");

        bytes4[] memory callSelectors = new bytes4[](3);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;

        bytes4[] memory delegateSelectors = new bytes4[](3);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;

        controller.__setDispatch(callSelectors[0], facets[0], delegateSelectors[0]);
        controller.__setDispatch(callSelectors[1], facets[1], delegateSelectors[1]);
        controller.__setDispatch(callSelectors[2], facets[1], delegateSelectors[2]);

        IController.Dispatch[] memory dispatches = controller.getDispatches(callSelectors);

        assertEq(dispatches.length, 3);

        assertEq(dispatches[0].facet,            facets[0]);
        assertEq(dispatches[0].delegateSelector, delegateSelectors[0]);
        assertEq(dispatches[1].facet,            facets[1]);
        assertEq(dispatches[1].delegateSelector, delegateSelectors[1]);
        assertEq(dispatches[2].facet,            facets[1]);
        assertEq(dispatches[2].delegateSelector, delegateSelectors[2]);
    }

    /**********************************************************************************************/
    /*** getWiring Tests                                                                        ***/
    /**********************************************************************************************/

    function test_getWiring() external {
        address facet = makeAddr("facet");

        bytes4[] memory callSelectors = new bytes4[](2);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;

        bytes4[] memory delegateSelectors = new bytes4[](2);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;

        controller.__addWire(facet, callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facet, callSelectors[1], delegateSelectors[1]);

        IController.Wire[] memory wiring = controller.getWiring(facet);

        assertEq(wiring.length, 2);
        assertEq(wiring[0].callSelector,     callSelectors[0]);
        assertEq(wiring[0].delegateSelector, delegateSelectors[0]);
        assertEq(wiring[1].callSelector,     callSelectors[1]);
        assertEq(wiring[1].delegateSelector, delegateSelectors[1]);
    }

    /**********************************************************************************************/
    /*** getWirings Tests                                                                       ***/
    /**********************************************************************************************/

    function test_getWirings() external {
        address[] memory facets = new address[](2);
        facets[0] = makeAddr("facet1");
        facets[1] = makeAddr("facet2");

        bytes4[] memory callSelectors = new bytes4[](3);
        callSelectors[0] = 0x12345678;
        callSelectors[1] = 0x89ABCDEF;
        callSelectors[2] = 0x11111111;

        bytes4[] memory delegateSelectors = new bytes4[](3);
        delegateSelectors[0] = 0x87654321;
        delegateSelectors[1] = 0xFECDAB98;
        delegateSelectors[2] = 0x33333333;

        controller.__addWire(facets[0], callSelectors[0], delegateSelectors[0]);
        controller.__addWire(facets[1], callSelectors[1], delegateSelectors[1]);
        controller.__addWire(facets[1], callSelectors[2], delegateSelectors[2]);

        IController.Wire[][] memory wirings = controller.getWirings(facets);

        assertEq(wirings.length, 2);

        assertEq(wirings[0].length, 1);

        assertEq(wirings[0][0].callSelector,     callSelectors[0]);
        assertEq(wirings[0][0].delegateSelector, delegateSelectors[0]);

        assertEq(wirings[1].length, 2);

        assertEq(wirings[1][0].callSelector,     callSelectors[1]);
        assertEq(wirings[1][0].delegateSelector, delegateSelectors[1]);
        assertEq(wirings[1][1].callSelector,     callSelectors[2]);
        assertEq(wirings[1][1].delegateSelector, delegateSelectors[2]);
    }

    /**********************************************************************************************/
    /*** Fallback Tests                                                                         ***/
    /**********************************************************************************************/

    function test_fallback_invalidCallDataLengthBoundary() external {
        ( bool success, bytes memory data ) = address(controller).call(hex"123456");

        assertEq(success, false);
        assertEq(data,    abi.encodeWithSelector(IController.InvalidCallDataLength.selector, 3));

        // Expect revert with CallSelectorNotWired error, but not with InvalidCallDataLength.
        ( success, data ) = address(controller).call(hex"12345678");

        assertEq(success, false);
        assertEq(data,    abi.encodeWithSelector(IController.CallSelectorNotWired.selector, bytes4(hex"12345678")));
    }

    function test_fallback_callSelectorNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(IController.CallSelectorNotWired.selector, IMockController.facetFoo.selector)
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

    function _expectAndMockAccessControlCall(address account, bool hasAdminRole) internal {
        _expectAndMockCall(
            accessControls,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector,
                DEFAULT_ADMIN_ROLE,
                account
            ),
            abi.encode(hasAdminRole)
        );
    }

    function _expectAndMockFactoryCall(address facet, bool isValid) internal {
        _expectAndMockCall(
            factory,
            abi.encodeWithSelector(
                IPAUFactory.isValidFacet.selector,
                facet
            ),
            abi.encode(isValid)
        );
    }

}
