// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations }               from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IFacet }                                from "../../../src/facets/IFacet.sol";
import { IERC4626Facet }                         from "../../../src/facets/erc4626/IERC4626Facet.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { ERC4626Facet } from "../../../src/facets/erc4626/ERC4626Facet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function getMaxExchangeRate(address token) external view returns (uint256);

    function getDepositRateLimitKey(address token, address asset) external pure returns (bytes32);

    function getWithdrawRateLimitKey(address token) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_ERC4626Facet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new ERC4626Facet());

        vm.label(facet, "ERC4626Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxExchangeRate.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getDepositRateLimitKey.selector,
            IERC4626Facet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getWithdrawRateLimitKey.selector,
            IERC4626Facet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("ERC4626_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "ERC4626_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setMaxExchangeRate Tests                                                               ***/
    /**********************************************************************************************/

    function test_setMaxExchangeRate_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);

        vm.expectRevert(abi.encodeWithSelector(
            IFacet.AccessControlUnauthorizedAccount.selector,
            relayer,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(relayer);
        controller.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_tokenZeroAddress() external {
        vm.expectRevert("ERC4626Facet/token-zero-address");
        vm.prank(admin);
        controller.setMaxExchangeRate(address(0), 1e18, 1e18);
    }

    function test_setMaxExchangeRate() external {
        address token = makeAddr("token");

        assertEq(controller.getMaxExchangeRate(token), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit IERC4626Facet.ERC4626MaxExchangeRateSet(token, 1e36);

        vm.prank(admin);
        controller.setMaxExchangeRate(token, 1e18, 1e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxExchangeRate(token), 1e36);

        vm.expectEmit(address(controller));
        emit IERC4626Facet.ERC4626MaxExchangeRateSet(token, 1e24);

        vm.prank(admin);
        controller.setMaxExchangeRate(token, 1e18, 1e6);

        assertEq(controller.getMaxExchangeRate(token), 1e24);

        vm.expectEmit(address(controller));
        emit IERC4626Facet.ERC4626MaxExchangeRateSet(token, 1e48);

        vm.prank(admin);
        controller.setMaxExchangeRate(token, 1e6, 1e18);

        assertEq(controller.getMaxExchangeRate(token), 1e48);
    }

    /**********************************************************************************************/
    /*** getDepositRateLimitKey Tests                                                           ***/
    /**********************************************************************************************/

    function test_getDepositRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_4626_DEPOSIT");
        address token     = makeAddr("token");
        address asset     = makeAddr("asset");

        assertEq(
            controller.getDepositRateLimitKey(token, asset),
            makeAddressAddressKey(keyPrefix, asset, token)
        );
    }

    /**********************************************************************************************/
    /*** getWithdrawRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getWithdrawRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_4626_WITHDRAW");
        address token     = makeAddr("token");

        assertEq(controller.getWithdrawRateLimitKey(token), makeAddressKey(keyPrefix, token));
    }

}
