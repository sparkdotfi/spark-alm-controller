// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { WrapProxyETHFacet } from "../../../src/facets/wrap-proxy-eth/WrapProxyETHFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_WrapProxyETHFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WrapProxyETHFacet/zero-weth");
        new WrapProxyETHFacet({ weth_ : address(0) });
    }

    function test_constructor() external {
        WrapProxyETHFacet facet = new WrapProxyETHFacet({ weth_ : makeAddr("weth") });

        assertEq(facet.weth(), makeAddr("weth"));
    }

}
