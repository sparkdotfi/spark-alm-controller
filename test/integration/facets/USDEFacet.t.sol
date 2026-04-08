// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { USDEFacet } from "../../../src/facets/usde/USDEFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_USDEFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroEthenaMinter() external {
        vm.expectRevert("USDEFacet/zero-ethenaMinter");
        new USDEFacet({
            ethenaMinter_ : address(0),
            susde_        : address(0),
            usdc_         : address(0),
            usde_         : address(0)
        });
    }

    function test_constructor_zeroSusde() external {
        vm.expectRevert("USDEFacet/zero-susde");
        new USDEFacet({
            ethenaMinter_ : makeAddr("ethenaMinter"),
            susde_        : address(0),
            usdc_         : address(0),
            usde_         : address(0)
        });
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("USDEFacet/zero-usdc");
        new USDEFacet({
            ethenaMinter_ : makeAddr("ethenaMinter"),
            susde_        : makeAddr("susde"),
            usdc_         : address(0),
            usde_         : address(0)
        });
    }

    function test_constructor_zeroUSDE() external {
        vm.expectRevert("USDEFacet/zero-usde");
        new USDEFacet({
            ethenaMinter_ : makeAddr("ethenaMinter"),
            susde_        : makeAddr("susde"),
            usdc_         : makeAddr("usdc"),
            usde_         : address(0)
        });
    }

    function test_constructor() external {
        USDEFacet facet = new USDEFacet({
            ethenaMinter_ : makeAddr("ethenaMinter"),
            susde_        : makeAddr("susde"),
            usdc_         : makeAddr("usdc"),
            usde_         : makeAddr("usde")
        });

        assertEq(facet.ethenaMinter(), makeAddr("ethenaMinter"));
        assertEq(facet.susde(),        makeAddr("susde"));
        assertEq(facet.usdc(),         makeAddr("usdc"));
        assertEq(facet.usde(),         makeAddr("usde"));
    }

}
