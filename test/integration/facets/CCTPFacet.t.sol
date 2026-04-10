// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICCTPFacet }              from "../../../src/facets/cctp/ICCTPFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { CCTPFacet } from "../../../src/facets/cctp/CCTPFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setCCTPMaxFeeCap(uint256 maxFeeCap) external;

    function setCCTPMintRecipient(uint32 destinationDomain, bytes32 recipient) external;

    function getCCTPMaxFeeCap() external view returns (uint256);

    function getCCTPMintRecipient(uint32 destinationDomain) external view returns (bytes32);

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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.getCCTPMaxFeeCap.selector,
            ICCTPFacet.maxFeeCap.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getCCTPMintRecipient.selector,
            ICCTPFacet.getMintRecipient.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.setCCTPMaxFeeCap.selector,
            ICCTPFacet.setMaxFeeCap.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.setCCTPMintRecipient.selector,
            ICCTPFacet.setMintRecipient.selector
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
    /*** setCCTPMaxFeeCap Tests                                                                  ***/
    /**********************************************************************************************/

    function test_setCCTPMaxFeeCap_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap() external {
        assertEq(controller.getCCTPMaxFeeCap(), 0);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMaxFeeCapSet({ maxFeeCap: 1e18 });

        vm.prank(admin);
        controller.setCCTPMaxFeeCap(1e18);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getCCTPMaxFeeCap(), 1e18);
    }

    /**********************************************************************************************/
    /*** setCCTPMintRecipient Tests                                                              ***/
    /**********************************************************************************************/

    function test_setCCTPMintRecipient_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setCCTPMintRecipient(1, mintRecipient1);
    }

    function test_setCCTPMintRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        controller.setCCTPMintRecipient(1, mintRecipient1);
    }

    function test_setCCTPMintRecipient() external {
        assertEq(controller.getCCTPMintRecipient(1), bytes32(0));
        assertEq(controller.getCCTPMintRecipient(2), bytes32(0));

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet({
            destinationDomain : 1,
            mintRecipient     : mintRecipient1
        });

        vm.prank(admin);
        controller.setCCTPMintRecipient(1, mintRecipient1);

        assertEq(controller.getCCTPMintRecipient(1), mintRecipient1);

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet({
            destinationDomain : 2,
            mintRecipient     : mintRecipient2
        });

        vm.prank(admin);
        controller.setCCTPMintRecipient(2, mintRecipient2);

        assertEq(controller.getCCTPMintRecipient(2), mintRecipient2);

        vm.record();

        vm.expectEmit(address(controller));
        emit ICCTPFacet.CCTPMintRecipientSet({
            destinationDomain : 1,
            mintRecipient     : mintRecipient2
        });

        vm.prank(admin);
        controller.setCCTPMintRecipient(1, mintRecipient2);

        assertEq(controller.getCCTPMintRecipient(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

}
