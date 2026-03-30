// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IController }     from "../../../src/interfaces/IController.sol";
import { IFacetBase }      from "../../../src/interfaces/facets/IFacetBase.sol";
import { IUniswapV4Facet } from "../../../src/interfaces/facets/IUniswapV4Facet.sol";

import { UniswapV4Facet } from "../../../src/libraries/UniswapV4Lib.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike is IController {

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

}

contract UniswapV4_TestBase is Controller_TestBase {

    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        // NOTE: Only wires the functions needed for the tests.
        //       If more functions are needed in future tests, they should be wired here.
        address facet = address(new UniswapV4Facet({
            permit2_         : makeAddr("permit2"),
            positionManager_ : makeAddr("positionManager"),
            router_          : makeAddr("router")
        }));

        vm.label(facet, "UniswapV4Facet");

        vm.startPrank(admin);

        // Controller.setMaxSlippage -> UniswapV4Facet.setMaxSlippage
        controller.setDispatch(
            IControllerLike.setMaxSlippage.selector,
            facet,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        // Controller.setTickLimits -> UniswapV4Facet.setTickLimits
        controller.setDispatch(
            IControllerLike.setTickLimits.selector,
            facet,
            IUniswapV4Facet.setTickLimits.selector
        );

        // Controller.getMaxSlippage -> UniswapV4Facet.getMaxSlippage
        controller.setDispatch(
            IControllerLike.getMaxSlippage.selector,
            facet,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        // Controller.getTickLimits -> UniswapV4Facet.getTickLimits
        controller.setDispatch(
            IControllerLike.getTickLimits.selector,
            facet,
            IUniswapV4Facet.getTickLimits.selector
        );

        vm.stopPrank();
    }

}

contract Controller_UniswapV4_Admin_Tests is UniswapV4_TestBase {

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
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setMaxSlippage(bytes32(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
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
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setTickLimits(bytes32(0), 0, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
        controller.setTickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setTickLimits_invalidTicks() external {
        vm.expectRevert("UniswapV4Facet/invalid-ticks");
        vm.prank(admin);
        controller.setTickLimits(bytes32(0), 1, 1, 1); // Reverts when lower >= upper

        vm.prank(admin);
        controller.setTickLimits(bytes32(0), 0, 1, 1); // lower must be less than upper

        vm.expectRevert("UniswapV4Facet/invalid-ticks");
        vm.prank(admin);
        controller.setTickLimits(bytes32(0), 0, 1, 0); // Reverts when maxTickSpacing is zero

        vm.prank(admin);
        controller.setTickLimits(bytes32(0), 0, 0, 0); // maxTickSpacing can only be 0 if all 0
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

}
