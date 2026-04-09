// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { USDSFacet } from "../../../src/facets/usds/USDSFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_USDSFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("USDSFacet/zero-usds");
        new USDSFacet(address(0), address(0));
    }

    function test_constructor_zeroVault() external {
        vm.expectRevert("USDSFacet/zero-vault");
        new USDSFacet(makeAddr("usds"), address(0));
    }

    function test_constructor() external {
        address usds  = makeAddr("usds");
        address vault = makeAddr("vault");

        USDSFacet facet = new USDSFacet(usds, vault);

        assertEq(facet.usds(),  usds);
        assertEq(facet.vault(), vault);
    }

}
