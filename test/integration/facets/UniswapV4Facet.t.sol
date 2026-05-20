// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IFacet }                                from "../../../src/facets/IFacet.sol";
import { IUniswapV4Facet }                       from "../../../src/facets/uniswap-v4/IUniswapV4Facet.sol";
import { makeAddressBytes32Key, makeBytes32Key } from "../../../src/libraries/RateLimitHelpers.sol";

import { UniswapV4Facet } from "../../../src/facets/uniswap-v4/UniswapV4Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setMaxSlippage(bytes32 poolId, uint256 maxSlippage) external;

    function setTickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    ) external;

    function getMaxSlippage(bytes32 poolId) external view returns (uint256);

    function getTickLimits(bytes32 poolId)
        external
        view
        returns (int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing);

    function getAggregateDepositRateLimitKey(bytes32 poolId) external pure returns (bytes32);

    function getAssetDepositRateLimitKey(bytes32 poolId, address token) external pure returns (bytes32);

    function getSwapRateLimitKey(bytes32 poolId, address token) external pure returns (bytes32);

    function getAggregateWithdrawRateLimitKey(bytes32 poolId) external pure returns (bytes32);

    function getAssetWithdrawRateLimitKey(bytes32 poolId, address token) external pure returns (bytes32);

    function permit2() external view returns (address);

    function positionManager() external view returns (address);

    function router() external view returns (address);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_UniswapV4Facet_Tests is Integration_TestBase {

    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new UniswapV4Facet({
            permit2_         : makeAddr("permit2"),
            positionManager_ : makeAddr("positionManager"),
            router_          : makeAddr("router")
        }));

        vm.label(facet, "UniswapV4Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](12);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxSlippage.selector,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.setTickLimits.selector,
            IUniswapV4Facet.setTickLimits.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxSlippage.selector,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getTickLimits.selector,
            IUniswapV4Facet.getTickLimits.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.getAggregateDepositRateLimitKey.selector,
            IUniswapV4Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getAssetDepositRateLimitKey.selector,
            IUniswapV4Facet.getAssetDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IControllerLike.getSwapRateLimitKey.selector,
            IUniswapV4Facet.getSwapRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IControllerLike.getAggregateWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IControllerLike.getAssetWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAssetWithdrawRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IControllerLike.permit2.selector,
            IUniswapV4Facet.permit2.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IControllerLike.positionManager.selector,
            IUniswapV4Facet.positionManager.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IControllerLike.router.selector,
            IUniswapV4Facet.router.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("UNISWAP_V4_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "UNISWAP_V4_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroPermit2() external {
        vm.expectRevert("UniswapV4Facet/zero-permit2");
        new UniswapV4Facet(address(0), address(0), address(0));
    }

    function test_constructor_zeroPositionManager() external {
        vm.expectRevert("UniswapV4Facet/zero-position-manager");
        new UniswapV4Facet(makeAddr("permit2"), address(0), address(0));
    }

    function test_constructor_zeroRouter() external {
        vm.expectRevert("UniswapV4Facet/zero-router");
        new UniswapV4Facet(makeAddr("permit2"), makeAddr("positionManager"), address(0));
    }

    function test_constructor() external {
        address permit2         = makeAddr("permit2");
        address positionManager = makeAddr("positionManager");
        address router          = makeAddr("router");

        UniswapV4Facet facet = new UniswapV4Facet(permit2, positionManager, router);

        assertEq(facet.permit2(),         permit2);
        assertEq(facet.positionManager(), positionManager);
        assertEq(facet.router(),          router);
    }

    /**********************************************************************************************/
    /*** Immutables Tests                                                                       ***/
    /**********************************************************************************************/

    function test_immutables() external {
        assertEq(controller.permit2(),         makeAddr("permit2"));
        assertEq(controller.positionManager(), makeAddr("positionManager"));
        assertEq(controller.router(),          makeAddr("router"));
    }

    /**********************************************************************************************/
    /*** setMaxSlippage Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setMaxSlippage_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxSlippage(bytes32(0), 0);
    }

    function test_setMaxSlippage_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setMaxSlippage(bytes32(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setMaxSlippage(bytes32(0), 0);
    }

    function test_setMaxSlippage_zeroPoolId() external {
        vm.expectRevert("UniswapV4Facet/zero-pool-id");
        vm.prank(admin);
        controller.setMaxSlippage(bytes32(0), 0.98e18);
    }

    function test_setMaxSlippage() external {
        vm.expectEmit(address(controller));
        emit IUniswapV4Facet.UniswapV4MaxSlippageSet(_POOL_ID, 0.98e18);

        vm.record();

        vm.prank(admin);
        controller.setMaxSlippage(_POOL_ID, 0.98e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxSlippage(_POOL_ID), 0.98e18);
    }

    /**********************************************************************************************/
    /*** setTickLimits Tests                                                                    ***/
    /**********************************************************************************************/

    function test_setTickLimits_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setTickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setTickLimits_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setTickLimits(bytes32(0), 0, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setTickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setTickLimits_zeroPoolId() external {
        vm.expectRevert("UniswapV4Facet/zero-pool-id");
        vm.prank(admin);
        controller.setTickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setTickLimits_invalidTicks() external {
        vm.expectRevert("UniswapV4Facet/invalid-ticks");
        vm.prank(admin);
        controller.setTickLimits(_POOL_ID, 1, 1, 1); // Reverts when lower >= upper

        vm.prank(admin);
        controller.setTickLimits(_POOL_ID, 0, 1, 1); // lower must be less than upper

        vm.expectRevert("UniswapV4Facet/invalid-ticks");
        vm.prank(admin);
        controller.setTickLimits(_POOL_ID, 0, 1, 0); // Reverts when maxTickSpacing is zero

        vm.prank(admin);
        controller.setTickLimits(_POOL_ID, 1, 2, 1);
    }

    function test_setTickLimits() external {
        vm.expectEmit(address(controller));
        emit IUniswapV4Facet.UniswapV4TickLimitsSet(_POOL_ID, -60, 60, 20);

        vm.record();

        vm.prank(admin);
        controller.setTickLimits(_POOL_ID, -60, 60, 20);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        ( int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing ) = controller.getTickLimits(_POOL_ID);

        assertEq(tickLowerMin,   -60);
        assertEq(tickUpperMax,   60);
        assertEq(maxTickSpacing, 20);
    }

    /**********************************************************************************************/
    /*** getAggregateDepositRateLimitKey Tests                                                  ***/
    /**********************************************************************************************/

    function test_getAggregateDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");

        assertEq(controller.getAggregateDepositRateLimitKey(_POOL_ID), makeBytes32Key(keyPrefix, _POOL_ID));
    }

    /**********************************************************************************************/
    /*** getAssetDepositRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_getAssetDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
        address token     = makeAddr("token");

        assertEq(
            controller.getAssetDepositRateLimitKey(_POOL_ID, token),
            makeAddressBytes32Key(keyPrefix, token, _POOL_ID)
        );
    }

    /**********************************************************************************************/
    /*** getSwapRateLimitKey Tests                                                              ***/
    /**********************************************************************************************/

    function test_getSwapRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V4_SWAP");
        address token     = makeAddr("token");

        assertEq(
            controller.getSwapRateLimitKey(_POOL_ID, token),
            makeAddressBytes32Key(keyPrefix, token, _POOL_ID)
        );
    }

    /**********************************************************************************************/
    /*** getAggregateWithdrawRateLimitKey Tests                                                 ***/
    /**********************************************************************************************/

    function test_getAggregateWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");

        assertEq(
            controller.getAggregateWithdrawRateLimitKey(_POOL_ID),
            makeBytes32Key(keyPrefix, _POOL_ID)
        );
    }

    /**********************************************************************************************/
    /*** getAssetWithdrawRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getAssetWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");
        address token     = makeAddr("token");

        assertEq(
            controller.getAssetWithdrawRateLimitKey(_POOL_ID, token),
            makeAddressBytes32Key(keyPrefix, token, _POOL_ID)
        );
    }

}
