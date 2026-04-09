// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { WSTETHFacet } from "../../../src/facets/wsteth/WSTETHFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_WSTETHFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WSTETHFacet/zero-weth");
        new WSTETHFacet(address(0), address(0), address(0));
    }

    function test_constructor_zeroWithdrawQueue() external {
        vm.expectRevert("WSTETHFacet/zero-withdrawQueue");
        new WSTETHFacet(makeAddr("weth"), address(0), address(0));
    }

    function test_constructor_zeroWSTETH() external {
        vm.expectRevert("WSTETHFacet/zero-wsteth");
        new WSTETHFacet(makeAddr("weth"), makeAddr("withdrawQueue"), address(0));
    }

    function test_constructor() external {
        address weth          = makeAddr("weth");
        address withdrawQueue = makeAddr("withdrawQueue");
        address wsteth        = makeAddr("wsteth");

        WSTETHFacet facet = new WSTETHFacet(weth, withdrawQueue, wsteth);

        assertEq(facet.weth(),          weth);
        assertEq(facet.withdrawQueue(), withdrawQueue);
        assertEq(facet.wsteth(),        wsteth);
    }

}
