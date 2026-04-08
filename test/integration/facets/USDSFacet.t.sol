// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { USDSFacet } from "../../../src/facets/usds/USDSFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

contract Controller_USDSFacet_Tests is Controller_TestBase {

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroVault() external {
        vm.expectRevert("USDSFacet/zero-vault");
        new USDSFacet({ vault_ : address(0), usds_ : address(0) });
    }

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("USDSFacet/zero-usds");
        new USDSFacet({ vault_ : makeAddr("vault"), usds_ : address(0) });
    }

    function test_constructor() external {
        USDSFacet facet = new USDSFacet({ vault_ : makeAddr("vault"), usds_ : makeAddr("usds") });

        assertEq(facet.vault(), makeAddr("vault"));
        assertEq(facet.usds(),  makeAddr("usds"));
    }

}
