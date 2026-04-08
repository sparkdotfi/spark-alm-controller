// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { MerklFacet } from "../../../src/facets/merkl/MerklFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_MerklFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroDistributor() external {
        vm.expectRevert("MerklFacet/zero-distributor");
        new MerklFacet({ distributor_ : address(0) });
    }

    function test_constructor() external {
        MerklFacet facet = new MerklFacet({ distributor_ : makeAddr("distributor") });

        assertEq(facet.distributor(), makeAddr("distributor"));
    }

}
