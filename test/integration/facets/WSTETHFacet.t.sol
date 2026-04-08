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
        new WSTETHFacet({ weth_ : address(0), withdrawQueue_ : address(0), wsteth_ : address(0) });
    }

    function test_constructor_zeroWithdrawQueue() external {
        vm.expectRevert("WSTETHFacet/zero-withdrawQueue");
        new WSTETHFacet({
            weth_          : makeAddr("weth"),
            withdrawQueue_ : address(0),
            wsteth_        : address(0)
        });
    }

    function test_constructor_zeroWSTETH() external {
        vm.expectRevert("WSTETHFacet/zero-wsteth");
        new WSTETHFacet({
            weth_          : makeAddr("weth"),
            withdrawQueue_ : makeAddr("withdrawQueue"),
            wsteth_        : address(0)
        });
    }

    function test_constructor() external {
        WSTETHFacet facet = new WSTETHFacet({
            weth_          : makeAddr("weth"),
            withdrawQueue_ : makeAddr("withdrawQueue"),
            wsteth_        : makeAddr("wsteth")
        });

        assertEq(facet.weth(),          makeAddr("weth"));
        assertEq(facet.withdrawQueue(), makeAddr("withdrawQueue"));
        assertEq(facet.wsteth(),        makeAddr("wsteth"));
    }

}
