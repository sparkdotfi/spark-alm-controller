// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IFacetBase } from "../../../src/facets/IFacetBase.sol";
import { IOTCFacet }  from "../../../src/facets/otc/IOTCFacet.sol";
import { OTCFacet }   from "../../../src/facets/otc/OTCFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setBuffer(address exchange, address buffer) external;

    function setDispatch(bytes4 callSelector, address facet, bytes4 delegateSelector) external;

    function setIsWhitelisted(address exchange, address asset, bool isWhitelisted) external;

    function setMaxSlippage(address exchange, uint256 maxSlippage) external;

    function setRechargeRate(address exchange, uint256 rechargeRate18) external;

    function getBuffer(address exchange) external view returns (address);

    function getIsWhitelisted(address exchange, address asset) external view returns (bool);

    function getMaxSlippage(address exchange) external view returns (uint256);

    function getRechargeRate(address exchange) external view returns (uint256);

}

abstract contract OTCFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        // NOTE: Only wires the functions needed for the tests.
        //       If more functions are needed in future tests, they should be wired here.
        address facet = address(new OTCFacet());

        vm.label(facet, "OTCFacet");

        vm.startPrank(admin);

        // Controller.setBuffer -> OTCFacet.setBuffer
        controller.setDispatch(
            IControllerLike.setBuffer.selector,
            facet,
            IOTCFacet.setBuffer.selector
        );

        // Controller.setMaxSlippage -> OTCFacet.setMaxSlippage
        controller.setDispatch(
            IControllerLike.setMaxSlippage.selector,
            facet,
            IOTCFacet.setMaxSlippage.selector
        );

        // Controller.setRechargeRate -> OTCFacet.setRechargeRate
        controller.setDispatch(
            IControllerLike.setRechargeRate.selector,
            facet,
            IOTCFacet.setRechargeRate.selector
        );

        // Controller.setIsWhitelisted -> OTCFacet.setIsWhitelisted
        controller.setDispatch(
            IControllerLike.setIsWhitelisted.selector,
            facet,
            IOTCFacet.setIsWhitelisted.selector
        );

        // Controller.getBuffer -> OTCFacet.getBuffer
        controller.setDispatch(
            IControllerLike.getBuffer.selector,
            facet,
            IOTCFacet.getBuffer.selector
        );

        // Controller.getMaxSlippage -> OTCFacet.getMaxSlippage
        controller.setDispatch(
            IControllerLike.getMaxSlippage.selector,
            facet,
            IOTCFacet.getMaxSlippage.selector
        );

        // Controller.getRechargeRate -> OTCFacet.getRechargeRate
        controller.setDispatch(
            IControllerLike.getRechargeRate.selector,
            facet,
            IOTCFacet.getRechargeRate.selector
        );

        // Controller.getIsWhitelisted -> OTCFacet.getIsWhitelisted
        controller.setDispatch(
            IControllerLike.getIsWhitelisted.selector,
            facet,
            IOTCFacet.getIsWhitelisted.selector
        );

        vm.stopPrank();
    }

}

contract Controller_OTCFacet_Admin_Tests is OTCFacet_TestBase {

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
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setBuffer(address(0), address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
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

    // TODO: test_setBuffer_notReady

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
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setMaxSlippage(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_zeroExchange() external {
        vm.expectRevert("OTCFacet/exchange-zero-address");
        vm.prank(admin);
        controller.setMaxSlippage(address(0), 0);
    }

    function test_setMaxSlippage_zeroMaxSlippage() external {
        vm.expectRevert("OTCFacet/max-slippage-zero");
        vm.prank(admin);
        controller.setMaxSlippage(address(1), 0);
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
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setRechargeRate(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
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
    /*** setIsWhitelisted Tests                                                                 ***/
    /**********************************************************************************************/

    function test_setIsWhitelisted_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setIsWhitelisted(address(0), address(0), false);
    }

    function test_setIsWhitelisted_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setIsWhitelisted(address(0), address(0), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacetBase.AccessControlUnauthorizedAccount.selector,
                relayer,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(relayer);
        controller.setIsWhitelisted(address(0), address(0), false);
    }

    function test_setIsWhitelisted_zeroExchange() external {
        vm.expectRevert("OTCFacet/exchange-zero-address");
        vm.prank(admin);
        controller.setIsWhitelisted(address(0), address(0), false);
    }

    function test_setIsWhitelisted_zeroAsset() external {
        vm.expectRevert("OTCFacet/asset-zero-address");
        vm.prank(admin);
        controller.setIsWhitelisted(address(1), address(0), false);
    }

    function test_setIsWhitelisted_bufferNoSet() external {
        vm.expectRevert("OTCFacet/otc-buffer-not-set");
        vm.prank(admin);
        controller.setIsWhitelisted(address(1), address(1), false);
    }

    function test_setIsWhitelisted() external {
        address asset    = makeAddr("asset");
        address buffer   = makeAddr("buffer");
        address exchange = makeAddr("exchange");

        vm.prank(admin);
        controller.setBuffer(exchange, buffer);

        assertEq(controller.getIsWhitelisted(exchange, asset), false);

        vm.expectEmit(address(controller));
        emit IOTCFacet.OTCWhitelistedAssetSet(exchange, asset, true);

        vm.record();

        vm.prank(admin);
        controller.setIsWhitelisted(exchange, asset, true);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getIsWhitelisted(exchange, asset), true);

        vm.expectEmit(address(controller));
        emit IOTCFacet.OTCWhitelistedAssetSet(exchange, asset, false);

        vm.prank(admin);
        controller.setIsWhitelisted(exchange, asset, false);

        assertEq(controller.getIsWhitelisted(exchange, asset), false);
    }

}
