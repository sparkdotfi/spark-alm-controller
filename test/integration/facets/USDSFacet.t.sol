// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IUSDSFacet }              from "../../../src/facets/usds/IUSDSFacet.sol";

import { USDSFacet } from "../../../src/facets/usds/USDSFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setVault(address vault) external;

    function updateIntegrations(bytes32[] memory integrationIds) external;

    function vault() external view returns (address);

}

contract Controller_USDSFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new USDSFacet(makeAddr("usds")));

        vm.label(facet, "USDSFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setVault.selector,
            IUSDSFacet.setVault.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.vault.selector,
            IUSDSFacet.vault.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("USDS_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "USDS_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroUSDS() external {
        vm.expectRevert("USDSFacet/zero-usds");
        new USDSFacet(address(0));
    }

    function test_constructor() external {
        address usds = makeAddr("usds");

        USDSFacet facet = new USDSFacet(usds);

        assertEq(facet.usds(), usds);
    }

    /**********************************************************************************************/
    /*** setVault Tests                                                                         ***/
    /**********************************************************************************************/

    function test_setVault_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setVault(makeAddr("vault"));
    }

    function test_setVault_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setVault(makeAddr("vault"));
    }

    function test_setVault_zeroAddress() external {
        vm.expectRevert("USDSFacet/zero-vault");
        vm.prank(admin);
        controller.setVault(address(0));
    }

    function test_setVault() external {
        assertEq(controller.vault(), address(0));

        address vault = makeAddr("vault");

        vm.record();

        vm.expectEmit(address(controller));
        emit IUSDSFacet.USDSVaultSet(vault);

        vm.prank(admin);
        controller.setVault(vault);

        assertEq(controller.vault(), vault);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

}
