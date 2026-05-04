// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IAaveFacet }              from "../../../src/facets/aave/IAaveFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import {
    makeAddressAddressAddressKey,
    makeAddressAddressKey
} from "../../../src/libraries/RateLimitHelpers.sol";

import { AaveFacet } from "../../../src/facets/aave/AaveFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setMaxSlippage(address aToken, uint256 maxSlippage) external;

    function getMaxSlippage(address aToken) external view returns (uint256);

    function getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32);

    function getWithdrawRateLimitKey(address aToken, address pool) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_AaveFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new AaveFacet());

        vm.label(facet, "AaveFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IAaveFacet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IAaveFacet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("AAVE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "AAVE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setMaxSlippage Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setMaxSlippage_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxSlippage(makeAddr("aToken"), 0.98e18);
    }

    function test_setMaxSlippage_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        controller.setMaxSlippage(makeAddr("aToken"), 0.98e18);
    }

    function test_setMaxSlippage_aTokenZeroAddress() external {
        vm.prank(admin);
        vm.expectRevert("AaveFacet/aToken-zero-address");
        controller.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() external {
        address aToken = makeAddr("aToken");

        assertEq(controller.getMaxSlippage(aToken), 0);

        vm.prank(admin);
        vm.expectEmit(address(controller));
        emit IAaveFacet.AaveMaxSlippageSet(aToken, 0.98e18);
        controller.setMaxSlippage(aToken, 0.98e18);

        assertEq(controller.getMaxSlippage(aToken), 0.98e18);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(controller));
        emit IAaveFacet.AaveMaxSlippageSet(aToken, 0.99e18);
        controller.setMaxSlippage(aToken, 0.99e18);

        assertEq(controller.getMaxSlippage(aToken), 0.99e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix       = keccak256("LIMIT_AAVE_DEPOSIT");
        address aToken          = makeAddr("aToken");
        address pool            = makeAddr("pool");
        address underlyingAsset = makeAddr("underlyingAsset");

        assertEq(
            controller.getDepositRateLimitKey(aToken, pool, underlyingAsset),
            makeAddressAddressAddressKey(keyPrefix, underlyingAsset, pool, aToken)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_AAVE_WITHDRAW");
        address aToken    = makeAddr("aToken");
        address pool      = makeAddr("pool");

        assertEq(
            controller.getWithdrawRateLimitKey(aToken, pool),
            makeAddressAddressKey(keyPrefix, pool, aToken)
        );
    }

}
