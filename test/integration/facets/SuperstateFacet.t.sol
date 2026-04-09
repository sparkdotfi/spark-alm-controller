// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { SuperstateFacet } from "../../../src/facets/superstate/SuperstateFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_SuperstateFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("SuperstateFacet/zero-usdc");
        new SuperstateFacet(address(0), address(0));
    }

    function test_constructor_zeroUSTB() external {
        vm.expectRevert("SuperstateFacet/zero-ustb");
        new SuperstateFacet(makeAddr("usdc"), address(0));
    }

    function test_constructor() external {
        address usdc = makeAddr("usdc");
        address ustb = makeAddr("ustb");

        SuperstateFacet facet = new SuperstateFacet(usdc, ustb);

        assertEq(facet.usdc(), usdc);
        assertEq(facet.ustb(), ustb);
    }

}
