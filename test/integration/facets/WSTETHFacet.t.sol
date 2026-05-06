// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IWSTETHFacet }            from "../../../src/facets/wsteth/IWSTETHFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { WSTETHFacet } from "../../../src/facets/wsteth/WSTETHFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function claimWithdrawRateLimitKey() external pure returns (bytes32);

    function depositRateLimitKey() external pure returns (bytes32);

    function requestWithdrawRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_WSTETHFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new WSTETHFacet(
            makeAddr("weth"),
            makeAddr("withdrawQueue"),
            makeAddr("wsteth")
        ));

        vm.label(facet, "WSTETHFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.claimWithdrawRateLimitKey.selector,
            IWSTETHFacet.claimWithdrawRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.depositRateLimitKey.selector,
            IWSTETHFacet.depositRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.requestWithdrawRateLimitKey.selector,
            IWSTETHFacet.requestWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("WSTETH_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "WSTETH_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WSTETHFacet/zero-weth");
        new WSTETHFacet(address(0), address(0), address(0));
    }

    function test_constructor_zeroWithdrawQueue() external {
        vm.expectRevert("WSTETHFacet/zero-withdrawQueue");
        new WSTETHFacet(makeAddr("weth"), address(0), address(0));
    }

    function test_constructor_zeroWSTETH() external {
        vm.expectRevert("WSTETHFacet/zero-wsteth");
        new WSTETHFacet(makeAddr("weth"), makeAddr("withdrawQueue"), address(0));
    }

    function test_constructor() external {
        address weth          = makeAddr("weth");
        address withdrawQueue = makeAddr("withdrawQueue");
        address wsteth        = makeAddr("wsteth");

        WSTETHFacet facet = new WSTETHFacet(weth, withdrawQueue, wsteth);

        assertEq(facet.weth(),          weth);
        assertEq(facet.withdrawQueue(), withdrawQueue);
        assertEq(facet.wsteth(),        wsteth);
    }

    /**********************************************************************************************/
    /*** claimWithdrawRateLimitKey Tests                                                        ***/
    /**********************************************************************************************/

    function test_claimWithdrawRateLimitKey() external {
        assertEq(controller.claimWithdrawRateLimitKey(), keccak256("LIMIT_WSTETH_CLAIM_WITHDRAW"));
    }

    /**********************************************************************************************/
    /*** depositRateLimitKey Tests                                                              ***/
    /**********************************************************************************************/

    function test_depositRateLimitKey() external {
        assertEq(controller.depositRateLimitKey(), keccak256("LIMIT_WSTETH_DEPOSIT"));
    }

    /**********************************************************************************************/
    /*** requestWithdrawRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_requestWithdrawRateLimitKey() external {
        assertEq(
            controller.requestWithdrawRateLimitKey(),
            keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW")
        );
    }

}
