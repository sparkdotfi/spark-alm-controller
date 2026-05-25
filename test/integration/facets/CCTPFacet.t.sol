// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICCTPFacet }              from "../../../src/facets/cctp/ICCTPFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeUint32Key }           from "../../../src/libraries/RateLimitHelpers.sol";

import { CCTPFacet } from "../../../src/facets/cctp/CCTPFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    function toCCTPRateLimitKey() external pure returns (bytes32);

    function getToDomainRateLimitKey(uint32 destinationDomain) external pure returns (bytes32);

    function getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp() external view returns (address);

    function usdc() external view returns (address);

    function DESTINATION_CALLER() external pure returns (bytes32);

    function MIN_FINALITY_THRESHOLD() external pure returns (uint32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_CCTPFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    bytes32 internal mintRecipient1 = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 internal mintRecipient2 = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new CCTPFacet(makeAddr("cctp"), makeAddr("usdc")));

        vm.label(facet, "CCTPFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setDomainParameters.selector,
            ICCTPFacet.setDomainParameters.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getDomainParameters.selector,
            ICCTPFacet.getDomainParameters.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.cctp.selector,
            ICCTPFacet.cctp.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.usdc.selector,
            ICCTPFacet.usdc.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IControllerLike.DESTINATION_CALLER.selector,
            ICCTPFacet.DESTINATION_CALLER.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IControllerLike.MIN_FINALITY_THRESHOLD.selector,
            ICCTPFacet.MIN_FINALITY_THRESHOLD.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("CCTP_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "CCTP_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroCCTP() external {
        vm.expectRevert("CCTPFacet/zero-cctp");
        new CCTPFacet(address(0), address(0));
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("CCTPFacet/zero-usdc");
        new CCTPFacet(makeAddr("cctp"), address(0));
    }

    function test_constructor() external {
        address cctp = makeAddr("cctp");
        address usdc = makeAddr("usdc");

        CCTPFacet facet = new CCTPFacet(cctp, usdc);

        assertEq(facet.cctp(), cctp);
        assertEq(facet.usdc(), usdc);
    }

    /**********************************************************************************************/
    /*** Immutables and Constants Tests                                                         ***/
    /**********************************************************************************************/

    function test_immutablesAndConstants() external {
        assertEq(controller.cctp(),                   makeAddr("cctp"));
        assertEq(controller.usdc(),                   makeAddr("usdc"));
        assertEq(controller.DESTINATION_CALLER(),     bytes32(0));
        assertEq(controller.MIN_FINALITY_THRESHOLD(), 2_000);
    }

    /**********************************************************************************************/
    /*** setDomainParameters Tests                                                              ***/
    /**********************************************************************************************/

    function test_setDomainParameters_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setDomainParameters(0, 0, 0, 0);
    }

    function test_setDomainParameters_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        controller.setDomainParameters(0, 0, 0, 0);
    }

    function test_setDomainParameters_zeroRecipient() external {
        vm.expectRevert("CCTPFacet/zero-recipient");
        vm.prank(admin);
        controller.setDomainParameters(1, bytes32(0), 0, 0);
    }

    function test_setDomainParameters_minFeeCapRateBoundary() external {
        vm.expectRevert("CCTPFacet/min-fee-cap-rate-too-high");
        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 1, 0);

        vm.expectRevert("CCTPFacet/min-fee-cap-rate-too-high");
        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 10_000, 9_999);

        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 9_999, 9_999);
    }

    function test_setDomainParameters_maxFeeCapRateBoundary() external {
        vm.expectRevert("CCTPFacet/max-fee-cap-rate-too-high");
        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 0, 10_000);

        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 0, 9_999);
    }

    function test_setDomainParameters() external {
        ( bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate ) = controller.getDomainParameters(1);

        assertEq(mintRecipient, bytes32(0));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPDomainParametersSet(1, mintRecipient1, 100, 1_000);

        vm.prank(admin);
        controller.setDomainParameters(1, mintRecipient1, 100, 1_000);

        ( mintRecipient, minFeeCapRate, maxFeeCapRate ) = controller.getDomainParameters(1);

        assertEq(mintRecipient, mintRecipient1);
        assertEq(minFeeCapRate, 100);
        assertEq(maxFeeCapRate, 1_000);
    }

    /**********************************************************************************************/
    /*** toCCTPRateLimitKey Tests                                                               ***/
    /**********************************************************************************************/

    function test_toCCTPRateLimitKey() external {
        assertEq(controller.toCCTPRateLimitKey(), keccak256("LIMIT_USDC_TO_CCTP"));
    }

    /**********************************************************************************************/
    /*** getToDomainRateLimitKey Tests                                                          ***/
    /**********************************************************************************************/

    function test_getToDomainRateLimitKey() external {
        bytes32 keyPrefix         = keccak256("LIMIT_USDC_TO_DOMAIN");
        uint32  destinationDomain = 42;

        assertEq(
            controller.getToDomainRateLimitKey(destinationDomain),
            makeUint32Key(keyPrefix, destinationDomain)
        );
    }

}
