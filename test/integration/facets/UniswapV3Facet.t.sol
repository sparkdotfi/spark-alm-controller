// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IFacetBase }      from "../../../src/facets/IFacetBase.sol";
import { IUniswapV3Facet } from "../../../src/facets/uniswap-v3/IUniswapV3Facet.sol";
import { UniswapV3Facet }  from "../../../src/facets/uniswap-v3/UniswapV3Facet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    function setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    function setMaxTickDelta(address pool, uint24 maxTickDelta) external;

    function setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    function getLiquidityTickBounds(address pool) external view returns (int24 lower, int24 upper);

    function getMaxSlippage(address pool) external view returns (uint256);

    function getMaxTickDelta(address pool) external view returns (uint24);

    function getTWAPSecondsAgo(address pool) external view returns (uint32);

}

abstract contract UniswapV3Facet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        vm.startPrank(facetValidator);

        address facet = address(new UniswapV3Facet(makeAddr("positionManager"), makeAddr("router")));

        vm.label(facet, "UniswapV3Facet");

        factory.setValidFacet(facet, true);

        vm.stopPrank();

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](9);

        wires[0] = IControllerLike.Wire(
            IControllerLike.setMaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.setMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[2] = IControllerLike.Wire(
            IControllerLike.setLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[3] = IControllerLike.Wire(
            IControllerLike.setLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[4] = IControllerLike.Wire(
            IControllerLike.setTWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[5] = IControllerLike.Wire(
            IControllerLike.getMaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[6] = IControllerLike.Wire(
            IControllerLike.getMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[7] = IControllerLike.Wire(
            IControllerLike.getLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[8] = IControllerLike.Wire(
            IControllerLike.getTWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
    }

}

contract Controller_UniswapV3Facet_Admin_Tests is UniswapV3Facet_TestBase {

    uint24 internal constant _MAX_TICK_DELTA = 887_272;

    int24 internal constant _MIN_UNISWAP_TICK = -887_272;
    int24 internal constant _MAX_UNISWAP_TICK = 887_272;

    /**********************************************************************************************/
    /*** setMaxSlippage Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setMaxSlippage_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxSlippage(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_zeroAddress() external {
        vm.expectRevert("UniswapV3Facet/pool-zero-address");
        vm.prank(admin);
        controller.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() external {
        address pool = makeAddr("pool");

        assertEq(controller.getMaxSlippage(pool), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit IUniswapV3Facet.UniswapV3MaxSlippageSet(pool, 0.99e18);

        vm.prank(admin);
        controller.setMaxSlippage(pool, 0.99e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxSlippage(pool), 0.99e18);
    }

    /**********************************************************************************************/
    /*** setMaxTickDelta Tests                                                                  ***/
    /**********************************************************************************************/

    function test_setMaxTickDelta_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxTickDelta(address(0), 0);
    }

    function test_setMaxTickDelta_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxTickDelta(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setMaxTickDelta(address(0), 0);
    }

    function test_setMaxTickDelta_outOfBoundsBoundary() external {
        address pool = makeAddr("pool");

        vm.expectRevert("UniswapV3Facet/max-tick-delta-oob");
        vm.prank(admin);
        controller.setMaxTickDelta(pool, 0);

        vm.prank(admin);
        vm.expectRevert("UniswapV3Facet/max-tick-delta-oob");
        controller.setMaxTickDelta(pool, _MAX_TICK_DELTA + 1);

        // Can set at boundary

        vm.prank(admin);
        controller.setMaxTickDelta(pool, 1);

        vm.prank(admin);
        controller.setMaxTickDelta(pool, _MAX_TICK_DELTA);
    }

    function test_setMaxTickDelta() external {
        address pool = makeAddr("pool");

        assertEq(controller.getMaxTickDelta(pool), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit IUniswapV3Facet.UniswapV3MaxTickDeltaSet(pool, 1);

        vm.prank(admin);
        controller.setMaxTickDelta(pool, 1);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxTickDelta(pool), 1);
    }

    /**********************************************************************************************/
    /*** setLiquidityLowerTickBound Tests                                                       ***/
    /**********************************************************************************************/

    function test_setLiquidityLowerTickBound_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setLiquidityLowerTickBound(address(0), 0);
    }

    function test_setLiquidityLowerTickBound_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setLiquidityLowerTickBound(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setLiquidityLowerTickBound(address(0), 0);
    }

    function test_setLiquidityLowerTickBound_outOfBoundsBoundary() external {
        address pool = makeAddr("pool");

        vm.expectRevert("UniswapV3Facet/lower-tick-oob");
        vm.prank(admin);
        controller.setLiquidityLowerTickBound(pool, _MIN_UNISWAP_TICK - 1);

        // First set an upper tick bound.
        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, 1000);

        // Try to set lower tick at the upper tick.
        vm.prank(admin);
        vm.expectRevert("UniswapV3Facet/lower-tick-oob");
        controller.setLiquidityLowerTickBound(pool, 1000);

        vm.prank(admin);
        controller.setLiquidityLowerTickBound(pool, _MIN_UNISWAP_TICK);

        vm.prank(admin);
        controller.setLiquidityLowerTickBound(pool, 999);
    }

    function test_setLiquidityLowerTickBound() external {
        address pool = makeAddr("pool");

        ( int24 lower, int24 upper ) = controller.getLiquidityTickBounds(pool);

        assertEq(lower, 0);
        assertEq(upper, 0);

        // First set an upper tick bound.
        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, 1000);

        vm.record();

        vm.expectEmit(address(controller));
        emit IUniswapV3Facet.UniswapV3LowerTickUpdated(pool, 500);

        vm.prank(admin);
        controller.setLiquidityLowerTickBound(pool, 500);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        ( lower, upper ) = controller.getLiquidityTickBounds(pool);

        assertEq(lower, 500);
        assertEq(upper, 1000);
    }

    /**********************************************************************************************/
    /*** setLiquidityUpperTickBound Tests                                                       ***/
    /**********************************************************************************************/

    function test_setLiquidityUpperTickBound_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setLiquidityUpperTickBound(address(0), 0);
    }

    function test_setLiquidityUpperTickBound_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setLiquidityUpperTickBound(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setLiquidityUpperTickBound(address(0), 0);
    }

    function test_setLiquidityUpperTickBound_outOfBoundsBoundary() external {
        address pool = makeAddr("pool");

        vm.expectRevert("UniswapV3Facet/upper-tick-oob");
        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, _MAX_UNISWAP_TICK + 1);

        vm.expectRevert("UniswapV3Facet/upper-tick-oob");
        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, 0); // Current lower tick is 0

        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, _MAX_UNISWAP_TICK);

        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, 1);
    }

    function test_setLiquidityUpperTickBound() external {
        address pool = makeAddr("pool");

        ( int24 lower, int24 upper ) = controller.getLiquidityTickBounds(pool);

        assertEq(lower, 0);
        assertEq(upper, 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit IUniswapV3Facet.UniswapV3UpperTickUpdated(pool, 1000);

        vm.prank(admin);
        controller.setLiquidityUpperTickBound(pool, 1000);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        ( lower, upper ) = controller.getLiquidityTickBounds(pool);

        assertEq(lower, 0);
        assertEq(upper, 1000);
    }

    /**********************************************************************************************/
    /*** setTWAPSecondsAgo Tests                                                                ***/
    /**********************************************************************************************/

    function test_setTWAPSecondsAgo_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setTWAPSecondsAgo(address(0), 0);
    }

    function test_setTWAPSecondsAgo_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setTWAPSecondsAgo(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacetBase.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setTWAPSecondsAgo(address(0), 0);
    }

    function test_setTWAPSecondsAgo_outOfBoundsBoundary() external {
        address pool = makeAddr("pool");

        vm.expectRevert("UniswapV3Facet/twap-seconds-ago-oob");
        vm.prank(admin);
        controller.setTWAPSecondsAgo(pool, uint32(type(int32).max));

        vm.prank(admin);
        controller.setTWAPSecondsAgo(pool, uint32(type(int32).max) - 1);
    }

    function test_setTWAPSecondsAgo() external {
        address pool = makeAddr("pool");

        assertEq(controller.getTWAPSecondsAgo(pool), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit IUniswapV3Facet.UniswapV3TWAPSecondsAgoUpdated(pool, 300);

        vm.prank(admin);
        controller.setTWAPSecondsAgo(pool, 300);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getTWAPSecondsAgo(pool), 300);
    }

}
