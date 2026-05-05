// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICCTPFacet }              from "../../../src/facets/cctp/ICCTPFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { makeUint32Key }           from "../../../src/libraries/RateLimitHelpers.sol";

import { CCTPFacet } from "../../../src/facets/cctp/CCTPFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setMaxFeeCap(uint256 maxFeeCap) external;

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient) external;

    function getMaxFeeCap() external view returns (uint256);

    function getMintRecipient(uint32 destinationDomain) external view returns (bytes32);

    function getToDomainRateLimitKey(uint32 destinationDomain) external pure returns (bytes32);

    function toCCTPRateLimitKey() external pure returns (bytes32);

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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxFeeCap.selector,
            ICCTPFacet.maxFeeCap.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getMintRecipient.selector,
            ICCTPFacet.getMintRecipient.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxFeeCap.selector,
            ICCTPFacet.setMaxFeeCap.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.setMintRecipient.selector,
            ICCTPFacet.setMintRecipient.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
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
    /*** setMaxFeeCap Tests                                                                     ***/
    /**********************************************************************************************/

    function test_setMaxFeeCap_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxFeeCap(1e18);
    }

    function test_setMaxFeeCap_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setMaxFeeCap(1e18);
    }

    function test_setMaxFeeCap() external {
        assertEq(controller.getMaxFeeCap(), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMaxFeeCapSet(1e18);

        vm.prank(admin);
        controller.setMaxFeeCap(1e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxFeeCap(), 1e18);
    }

    /**********************************************************************************************/
    /*** setMintRecipient Tests                                                                 ***/
    /**********************************************************************************************/

    function test_setMintRecipient_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        controller.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient_zeroAddress() external {
        vm.expectRevert("CCTPFacet/zero-recipient");
        vm.prank(admin);
        controller.setMintRecipient(1, bytes32(0));
    }

    function test_setMintRecipient() external {
        assertEq(controller.getMintRecipient(1), bytes32(0));
        assertEq(controller.getMintRecipient(2), bytes32(0));

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet(1, mintRecipient1);

        vm.prank(admin);
        controller.setMintRecipient(1, mintRecipient1);

        assertEq(controller.getMintRecipient(1), mintRecipient1);

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet(2, mintRecipient2);

        vm.prank(admin);
        controller.setMintRecipient(2, mintRecipient2);

        assertEq(controller.getMintRecipient(2), mintRecipient2);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet(1, mintRecipient2);

        vm.prank(admin);
        controller.setMintRecipient(1, mintRecipient2);

        assertEq(controller.getMintRecipient(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice(address(controller));
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
