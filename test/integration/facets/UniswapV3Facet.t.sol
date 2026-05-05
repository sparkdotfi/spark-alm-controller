// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IFacet }                                from "../../../src/facets/IFacet.sol";
import { IUniswapV3Facet }                       from "../../../src/facets/uniswap-v3/IUniswapV3Facet.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { UniswapV3Facet } from "../../../src/facets/uniswap-v3/UniswapV3Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    function setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    function setMaxTickDelta(address pool, uint24 maxTickDelta) external;

    function setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    function getLiquidityTickBounds(address pool) external view returns (int24 lower, int24 upper);

    function getMaxSlippage(address pool) external view returns (uint256);

    function getMaxTickDelta(address pool) external view returns (uint24);

    function getTWAPSecondsAgo(address pool) external view returns (uint32);

    function getAggregateDepositRateLimitKey(address pool) external pure returns (bytes32);

    function getAssetDepositRateLimitKey(address pool, address token) external pure returns (bytes32);

    function getSwapRateLimitKey(address pool, address token) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address pool) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_UniswapV3Facet_Tests is Integration_TestBase {

    uint24 internal constant _MAX_TICK_DELTA = 887_272;

    int24 internal constant _MIN_UNISWAP_TICK = -887_272;
    int24 internal constant _MAX_UNISWAP_TICK = 887_272;

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new UniswapV3Facet(makeAddr("positionManager"), makeAddr("router")));

        vm.label(facet, "UniswapV3Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](13);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.setLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.setLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.setTWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IControllerLike.getLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IControllerLike.getTWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IControllerLike.getAggregateDepositRateLimitKey.selector,
            IUniswapV3Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IControllerLike.getAssetDepositRateLimitKey.selector,
            IUniswapV3Facet.getAssetDepositRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IControllerLike.getSwapRateLimitKey.selector,
            IUniswapV3Facet.getSwapRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("UNISWAP_V3_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "UNISWAP_V3_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroPositionManager() external {
        vm.expectRevert("UniswapV3Facet/zero-position-manager");
        new UniswapV3Facet(address(0), address(0));
    }

    function test_constructor_zeroRouter() external {
        vm.expectRevert("UniswapV3Facet/zero-router");
        new UniswapV3Facet(makeAddr("positionManager"), address(0));
    }

    function test_constructor() external {
        address positionManager = makeAddr("positionManager");
        address router          = makeAddr("router");

        UniswapV3Facet facet = new UniswapV3Facet(positionManager, router);

        assertEq(facet.positionManager(), positionManager);
        assertEq(facet.router(),          router);
    }

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
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxSlippage(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            allocator,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(allocator);
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
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxTickDelta(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            allocator,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(allocator);
        controller.setMaxTickDelta(address(0), 0);
    }

    function test_setMaxTickDelta_zeroAddress() external {
        vm.expectRevert("UniswapV3Facet/pool-zero-address");
        vm.prank(admin);
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
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setLiquidityLowerTickBound(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            allocator,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(allocator);
        controller.setLiquidityLowerTickBound(address(0), 0);
    }

    function test_setLiquidityLowerTickBound_zeroAddress() external {
        vm.expectRevert("UniswapV3Facet/pool-zero-address");
        vm.prank(admin);
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
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setLiquidityUpperTickBound(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            allocator,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(allocator);
        controller.setLiquidityUpperTickBound(address(0), 0);
    }

    function test_setLiquidityUpperTickBound_zeroAddress() external {
        vm.expectRevert("UniswapV3Facet/pool-zero-address");
        vm.prank(admin);
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
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setTWAPSecondsAgo(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            allocator,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(allocator);
        controller.setTWAPSecondsAgo(address(0), 0);
    }

    function test_setTWAPSecondsAgo_zeroAddress() external {
        vm.expectRevert("UniswapV3Facet/pool-zero-address");
        vm.prank(admin);
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

    /**********************************************************************************************/
    /*** getAggregateDepositRateLimitKey Tests                                                  ***/
    /**********************************************************************************************/

    function test_getAggregateDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V3_DEPOSIT");
        address pool      = makeAddr("pool");

        assertEq(
            controller.getAggregateDepositRateLimitKey(pool),
            makeAddressKey(keyPrefix, pool)
        );
    }

    /**********************************************************************************************/
    /*** getAssetDepositRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getAssetDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V3_DEPOSIT");
        address pool      = makeAddr("pool");
        address token     = makeAddr("token");

        assertEq(
            controller.getAssetDepositRateLimitKey(pool, token),
            makeAddressAddressKey(keyPrefix, token, pool)
        );
    }

    /**********************************************************************************************/
    /*** getSwapRateLimitKey Tests                                                              ***/
    /**********************************************************************************************/

    function test_getSwapRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V3_SWAP");
        address pool      = makeAddr("pool");
        address token     = makeAddr("token");

        assertEq(
            controller.getSwapRateLimitKey(pool, token),
            makeAddressAddressKey(keyPrefix, token, pool)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V3_WITHDRAW");
        address pool      = makeAddr("pool");

        assertEq(controller.getWithdrawRateLimitKey(pool), makeAddressKey(keyPrefix, pool));
    }

}
