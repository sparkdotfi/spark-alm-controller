// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IFacet }                  from "../../../src/facets/IFacet.sol";
import { IOTCFacet }               from "../../../src/facets/otc/IOTCFacet.sol";
import { makeAddressAddressKey }   from "../../../src/libraries/RateLimitHelpers.sol";

import { OTCFacet } from "../../../src/facets/otc/OTCFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setBuffer(address exchange, address buffer) external;

    function setMaxSlippage(address exchange, uint256 maxSlippage) external;

    function setRechargeRate(address exchange, uint256 normalizedRate) external;

    function getBuffer(address exchange) external view returns (address);

    function getMaxSlippage(address exchange) external view returns (uint256);

    function getRechargeRate(address exchange) external view returns (uint256);

    function getSendRateLimitKey(address exchange, address asset) external pure returns (bytes32);

    function getClaimRateLimitKey(address exchange, address asset) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_OTCFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new OTCFacet());

        vm.label(facet, "OTCFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setBuffer.selector,
            IOTCFacet.setBuffer.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxSlippage.selector,
            IOTCFacet.setMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.setRechargeRate.selector,
            IOTCFacet.setRechargeRate.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getBuffer.selector,
            IOTCFacet.getBuffer.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxSlippage.selector,
            IOTCFacet.getMaxSlippage.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getRechargeRate.selector,
            IOTCFacet.getRechargeRate.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IControllerLike.getSendRateLimitKey.selector,
            IOTCFacet.getSendRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IControllerLike.getClaimRateLimitKey.selector,
            IOTCFacet.getClaimRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("OTC_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "OTC_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setBuffer Tests                                                                        ***/
    /**********************************************************************************************/

    function test_setBuffer_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setBuffer(address(0), address(0));
    }

    function test_setBuffer_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setBuffer(address(0), address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setBuffer(address(0), address(0));
    }

    function test_setBuffer_zeroExchange() external {
        vm.expectRevert("OTCFacet/exchange-zero-address");
        vm.prank(admin);
        controller.setBuffer(address(0), address(0));
    }

    function test_setBuffer_zeroBuffer() external {
        vm.expectRevert("OTCFacet/otcBuffer-zero-address");
        vm.prank(admin);
        controller.setBuffer(address(1), address(0));
    }

    function test_setBuffer_equalsBuffer() external {
        vm.expectRevert("OTCFacet/exchange-equals-otcBuffer");
        vm.prank(admin);
        controller.setBuffer(address(1), address(1));
    }

    function test_setBuffer() external {
        address buffer   = makeAddr("buffer");
        address exchange = makeAddr("exchange");

        assertEq(controller.getBuffer(exchange), address(0));

        vm.expectEmit(address(controller));
        emit IOTCFacet.OTCBufferSet(exchange, buffer);

        vm.record();

        vm.prank(admin);
        controller.setBuffer(exchange, buffer);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getBuffer(exchange), buffer);
    }

    /**********************************************************************************************/
    /*** setMaxSlippage Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setMaxSlippage_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setMaxSlippage(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_zeroExchange() external {
        vm.expectRevert("OTCFacet/exchange-zero-address");
        vm.prank(admin);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage() external {
        address exchange = makeAddr("exchange");

        assertEq(controller.getMaxSlippage(exchange), 0);

        vm.expectEmit(address(controller));
        emit IOTCFacet.OTCMaxSlippageSet(exchange, 0.98e18);

        vm.record();

        vm.prank(admin);
        controller.setMaxSlippage(exchange, 0.98e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxSlippage(exchange), 0.98e18);
    }

    /**********************************************************************************************/
    /*** setRechargeRate Tests                                                                  ***/
    /**********************************************************************************************/

    function test_setRechargeRate_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setRechargeRate(address(0), 0);
    }

    function test_setRechargeRate_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setRechargeRate(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setRechargeRate(address(0), 0);
    }

    function test_setRechargeRate_zeroExchange() external {
        vm.expectRevert("OTCFacet/exchange-zero-address");
        vm.prank(admin);
        controller.setRechargeRate(address(0), 0);
    }

    function test_setRechargeRate() external {
        address exchange = makeAddr("exchange");

        assertEq(controller.getRechargeRate(exchange), 0);

        vm.expectEmit(address(controller));
        emit IOTCFacet.OTCRechargeRateSet(exchange, 1e18);

        vm.record();

        vm.prank(admin);
        controller.setRechargeRate(exchange, 1e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getRechargeRate(exchange), 1e18);
    }

    /**********************************************************************************************/
    /*** getSendRateLimitKey Tests                                                               ***/
    /**********************************************************************************************/

    function test_getSendRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_OTC_SEND");
        address exchange  = makeAddr("exchange");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getSendRateLimitKey(exchange, asset),
            makeAddressAddressKey(keyPrefix, asset, exchange)
        );
    }

    /**********************************************************************************************/
    /*** getClaimRateLimitKey Tests                                                              ***/
    /**********************************************************************************************/

    function test_getClaimRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_OTC_CLAIM");
        address exchange  = makeAddr("exchange");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getClaimRateLimitKey(exchange, asset),
            makeAddressAddressKey(keyPrefix, asset, exchange)
        );
    }

}
