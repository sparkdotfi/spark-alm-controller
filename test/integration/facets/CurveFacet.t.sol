// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICurveFacet } from "../../../src/facets/curve/ICurveFacet.sol";
import { CurveFacet }  from "../../../src/facets/curve/CurveFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function setCurveMaxSlippage(address pool, uint256 maxSlippage) external;

    function getCurveMaxSlippage(address pool) external view returns (uint256);

}

abstract contract CurveFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        vm.startPrank(facetValidator);

        address facet = address(new CurveFacet());

        vm.label(facet, "CurveFacet");

        factory.setValidFacet(facet, true);

        vm.stopPrank();

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](2);

        wires[0] = IControllerLike.Wire(
            IControllerLike.setCurveMaxSlippage.selector,
            ICurveFacet.setMaxSlippage.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.getCurveMaxSlippage.selector,
            ICurveFacet.getMaxSlippage.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
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
        emit ICurveFacet.CurveMaxSlippageSet({ pool: pool, maxSlippage: 0.98e18 });

        vm.prank(admin);
        controller.setCurveMaxSlippage(pool, 0.98e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getCurveMaxSlippage(pool), 0.98e18);

        vm.expectEmit(address(controller));
        emit ICurveFacet.CurveMaxSlippageSet({ pool: pool, maxSlippage: 0.99e18 });

        vm.prank(admin);
        controller.setCurveMaxSlippage(pool, 0.99e18);

        assertEq(controller.getCurveMaxSlippage(pool), 0.99e18);
    }

}
