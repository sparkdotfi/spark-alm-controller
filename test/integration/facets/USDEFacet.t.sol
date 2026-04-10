// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { USDEFacet } from "../../../src/facets/usde/USDEFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

contract Controller_USDEFacet_Tests is Integration_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroEthenaMinter() external {
        vm.expectRevert("USDEFacet/zero-ethenaMinter");
        new USDEFacet(address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroSusde() external {
        vm.expectRevert("USDEFacet/zero-susde");
        new USDEFacet(makeAddr("ethenaMinter"), address(0), address(0), address(0));
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("USDEFacet/zero-usdc");
        new USDEFacet(makeAddr("ethenaMinter"), makeAddr("susde"), address(0), address(0));
    }

    function test_constructor_zeroUSDE() external {
        vm.expectRevert("USDEFacet/zero-usde");
        new USDEFacet(makeAddr("ethenaMinter"), makeAddr("susde"), makeAddr("usdc"), address(0));
    }

    function test_constructor() external {
        address ethenaMinter = makeAddr("ethenaMinter");
        address susde        = makeAddr("susde");
        address usdc         = makeAddr("usdc");
        address usde         = makeAddr("usde");

        USDEFacet facet = new USDEFacet(ethenaMinter, susde, usdc, usde);

        assertEq(facet.ethenaMinter(), ethenaMinter);
        assertEq(facet.susde(),        susde);
        assertEq(facet.usdc(),         usdc);
        assertEq(facet.usde(),         usde);
    }

}
