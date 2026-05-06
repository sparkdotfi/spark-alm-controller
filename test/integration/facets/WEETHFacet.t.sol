// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IWEETHFacet }             from "../../../src/facets/weeth/IWEETHFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import {
    makeAddressAddressAddressKey,
    makeAddressAddressKey,
    makeAddressKey
} from "../../../src/libraries/RateLimitHelpers.sol";

import { WEETHFacet } from "../../../src/facets/weeth/WEETHFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function getClaimWithdrawRateLimitKey(address weethModule) external pure returns (bytes32);

    function getDepositRateLimitKey(address eeth, address liquidityPool) external pure returns (bytes32);

    function getRequestWithdrawRateLimitKey(address weethModule, address eeth, address liquidityPool)
        external
        pure
        returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_WEETHFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new WEETHFacet(makeAddr("weeth"), makeAddr("weth")));

        vm.label(facet, "WEETHFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimWithdrawRateLimitKey.selector,
            IWEETHFacet.getClaimWithdrawRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IWEETHFacet.getDepositRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getRequestWithdrawRateLimitKey.selector,
            IWEETHFacet.getRequestWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("WEETH_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "WEETH_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroWEETH() external {
        vm.expectRevert("WEETHFacet/zero-weeth");
        new WEETHFacet(address(0), address(0));
    }

    function test_constructor_zeroWETH() external {
        vm.expectRevert("WEETHFacet/zero-weth");
        new WEETHFacet(makeAddr("weeth"), address(0));
    }

    function test_constructor() external {
        address weeth = makeAddr("weeth");
        address weth  = makeAddr("weth");

        WEETHFacet facet = new WEETHFacet(weeth, weth);

        assertEq(facet.weeth(), weeth);
        assertEq(facet.weth(),  weth);
    }

    /**********************************************************************************************/
    /*** getClaimWithdrawRateLimitKey Tests                                                      ***/
    /**********************************************************************************************/

    function test_getClaimWithdrawRateLimitKey() external {
        bytes32 keyPrefix   = keccak256("LIMIT_WEETH_CLAIM_WITHDRAW");
        address weethModule = makeAddr("weethModule");

        assertEq(controller.getClaimWithdrawRateLimitKey(weethModule), makeAddressKey(keyPrefix, weethModule));
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix     = keccak256("LIMIT_WEETH_DEPOSIT");
        address eeth          = makeAddr("eeth");
        address liquidityPool = makeAddr("liquidityPool");

        assertEq(
            controller.getDepositRateLimitKey(eeth, liquidityPool),
            makeAddressAddressKey(keyPrefix, eeth, liquidityPool)
        );
    }

    /**********************************************************************************************/
    /*** getRequestWithdrawRateLimitKey Tests                                                   ***/
    /**********************************************************************************************/

    function test_getRequestWithdrawRateLimitKey() external {
        bytes32 keyPrefix     = keccak256("LIMIT_WEETH_REQUEST_WITHDRAW");
        address weethModule   = makeAddr("weethModule");
        address eeth          = makeAddr("eeth");
        address liquidityPool = makeAddr("liquidityPool");

        assertEq(
            controller.getRequestWithdrawRateLimitKey(weethModule, eeth, liquidityPool),
            makeAddressAddressAddressKey(keyPrefix, eeth, liquidityPool, weethModule)
        );
    }

}
