// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { WEETHFacet } from "../../../src/facets/weeth/WEETHFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_WEETHFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWEETH() external {
        vm.expectRevert("WEETHFacet/zero-weeth");
        new WEETHFacet(address(0), address(0));
    }

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WEETHFacet/zero-weth");
        new WEETHFacet(makeAddr("weeth"), address(0));
    }

    function test_constructor() external {
        address weeth = makeAddr("weeth");
        address weth  = makeAddr("weth");

        WEETHFacet facet = new WEETHFacet(weeth, weth);

        assertEq(facet.weeth(), weeth);
        assertEq(facet.weth(),  weth);
    }

}
