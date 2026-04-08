// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { WEETHFacet } from "../../../src/facets/weeth/WEETHFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_WEETHFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WEETHFacet/zero-weth");
        new WEETHFacet({ weth_ : address(0), weeth_ : address(0) });
    }

    function test_constructor_zeroWEETH() external {
        vm.expectRevert("WEETHFacet/zero-weeth");
        new WEETHFacet({ weth_ : makeAddr("weth"), weeth_ : address(0) });
    }

    function test_constructor() external {
        WEETHFacet facet = new WEETHFacet({ weth_ : makeAddr("weth"), weeth_ : makeAddr("weeth") });

        assertEq(facet.weth(),  makeAddr("weth"));
        assertEq(facet.weeth(), makeAddr("weeth"));
    }

}
