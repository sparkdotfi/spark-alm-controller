// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICurveFacet } from "../../../src/interfaces/facets/ICurveFacet.sol";
import { IController } from "../../../src/interfaces/IController.sol";

import { CurveFacet } from "../../../src/libraries/CurveLib.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike is IController {

    function getCurveMaxSlippage(address pool) external view returns (uint256);

    function setCurveMaxSlippage(address pool, uint256 maxSlippage) external;

}

contract CurveFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        // NOTE: Only wires the functions needed for the tests.
        //       If more functions are needed in future tests, they should be wired here.
        address facet = address(new CurveFacet());

        vm.startPrank(admin);

        vm.label(facet, "CurveFacet");

        // Controller.setCurveMaxSlippage() -> CurveFacet.setMaxSlippage()
        controller.setDispatch(
            IControllerLike.setCurveMaxSlippage.selector,
            facet,
            ICurveFacet.setMaxSlippage.selector
        );

        // Controller.getCurveMaxSlippage() -> CurveFacet.getMaxSlippage()
        controller.setDispatch(
            IControllerLike.getCurveMaxSlippage.selector,
            facet,
            ICurveFacet.getMaxSlippage.selector
        );

        vm.stopPrank();
    }

}

contract Controller_CurveFacet_Admin_Tests is CurveFacet_TestBase {

    function test_setCurveMaxSlippage_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setCurveMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setCurveMaxSlippage_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        controller.setCurveMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setCurveMaxSlippage_poolZeroAddress() external {
        vm.expectRevert("CurveFacet/pool-zero-address");
        vm.prank(admin);
        controller.setCurveMaxSlippage(address(0), 0.98e18);
    }

    function test_setCurveMaxSlippage() external {
        address pool = makeAddr("pool");

        assertEq(controller.getCurveMaxSlippage(pool), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICurveFacet.CurveMaxSlippageSet(pool, 0.98e18);

        vm.prank(admin);
        controller.setCurveMaxSlippage(pool, 0.98e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getCurveMaxSlippage(pool), 0.98e18);

        vm.expectEmit(address(controller));
        emit ICurveFacet.CurveMaxSlippageSet(pool, 0.99e18);

        vm.prank(admin);
        controller.setCurveMaxSlippage(pool, 0.99e18);

        assertEq(controller.getCurveMaxSlippage(pool), 0.99e18);
    }

}
