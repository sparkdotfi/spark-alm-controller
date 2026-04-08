// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICCTPFacet } from "../../../src/facets/cctp/ICCTPFacet.sol";
import { CCTPFacet }  from "../../../src/facets/cctp/CCTPFacet.sol";

import { Controller_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function addWires(address facet, Wire[] calldata wires) external;

    function setCCTPMaxFeeCap(uint256 maxFeeCap) external;

    function setCCTPMintRecipient(uint32 destinationDomain, bytes32 recipient) external;

    function getCCTPMaxFeeCap() external view returns (uint256);

    function getCCTPMintRecipient(uint32 destinationDomain) external view returns (bytes32);

}

abstract contract CCTPFacet_TestBase is Controller_TestBase {

    IControllerLike internal controller;

    bytes32 internal mintRecipient1 = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 internal mintRecipient2 = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    function setUp() external {
        controller = IControllerLike(_deploy());

        vm.startPrank(facetValidator);

        address facet = address(new CCTPFacet(makeAddr("cctp"), makeAddr("usdc")));

        vm.label(facet, "CCTPFacet");

        factory.setValidFacet(facet, true);

        vm.stopPrank();

        IControllerLike.Wire[] memory wires = new IControllerLike.Wire[](4);

        wires[0] = IControllerLike.Wire(
            IControllerLike.getCCTPMaxFeeCap.selector,
            ICCTPFacet.maxFeeCap.selector
        );

        wires[1] = IControllerLike.Wire(
            IControllerLike.getCCTPMintRecipient.selector,
            ICCTPFacet.getMintRecipient.selector
        );

        wires[2] = IControllerLike.Wire(
            IControllerLike.setCCTPMaxFeeCap.selector,
            ICCTPFacet.setMaxFeeCap.selector
        );

        wires[3] = IControllerLike.Wire(
            IControllerLike.setCCTPMintRecipient.selector,
            ICCTPFacet.setMintRecipient.selector
        );

        vm.prank(admin);
        controller.addWires(facet, wires);
    }

}

contract Controller_CCTPFacet_SetCCTPMaxFeeCap_Tests is CCTPFacet_TestBase {

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

}

contract Controller_CCTPFacet_SetCCTPMintRecipient_Tests is CCTPFacet_TestBase {

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
