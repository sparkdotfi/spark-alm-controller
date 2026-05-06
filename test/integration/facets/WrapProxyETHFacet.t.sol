// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IWrapProxyETHFacet }      from "../../../src/facets/wrap-proxy-eth/IWrapProxyETHFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { WrapProxyETHFacet } from "../../../src/facets/wrap-proxy-eth/WrapProxyETHFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function wrapRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_WrapProxyETHFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new WrapProxyETHFacet(makeAddr("weth")));

        vm.label(facet, "WrapProxyETHFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.wrapRateLimitKey.selector,
            IWrapProxyETHFacet.wrapRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("WRAP_PROXY_ETH_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "WRAP_PROXY_ETH_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }


    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WrapProxyETHFacet/zero-weth");
        new WrapProxyETHFacet(address(0));
    }

    function test_constructor() external {
        address weth = makeAddr("weth");

        WrapProxyETHFacet facet = new WrapProxyETHFacet(weth);

        assertEq(facet.weth(), weth);
    }

    /**********************************************************************************************/
    /*** wrapRateLimitKey Tests                                                                 ***/
    /**********************************************************************************************/

    function test_wrapRateLimitKey() external {
        assertEq(controller.wrapRateLimitKey(), keccak256("LIMIT_WRAP_PROXY_ETH"));
    }

}
