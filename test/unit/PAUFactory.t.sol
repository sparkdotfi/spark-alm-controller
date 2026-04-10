// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUFactory } from "../../src/interfaces/IPAUFactory.sol";

import { PAUFactory } from "../../src/PAUFactory.sol";

contract PAUFactory_Tests is Test {

    address internal beacon   = makeAddr("beacon");
    address internal deployer = makeAddr("deployer");

    PAUFactory internal factory;

    function setUp() external {
        vm.prank(deployer);
        factory = new PAUFactory(beacon);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroBeacon() external {
        vm.expectRevert(IPAUFactory.ZeroBeacon.selector);
        new PAUFactory(address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Tests                                                                    ***/
    /**********************************************************************************************/

    function test_initialState() external {
        assertEq(factory.beacon(), beacon);
    }

}
