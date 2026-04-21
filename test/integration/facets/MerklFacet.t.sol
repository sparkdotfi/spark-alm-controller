// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";
import { IMerklFacet }             from "../../../src/facets/merkl/IMerklFacet.sol";

import { MerklFacet } from "../../../src/facets/merkl/MerklFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setDistributor(address distributor) external;

    function updateIntegrations(bytes32[] memory integrationIds) external;

    function distributor() external view returns (address);

}

contract Controller_MerklFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new MerklFacet());

        vm.label(facet, "MerklFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setDistributor.selector,
            IMerklFacet.setDistributor.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.distributor.selector,
            IMerklFacet.distributor.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("MERKL_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "MERKL_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setDistributor Tests                                                                   ***/
    /**********************************************************************************************/

    function test_setDistributor_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setDistributor(address(0));
    }

    function test_setDistributor_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(unauthorized);
        controller.setDistributor(address(0));
    }

    function test_setDistributor_zeroAddress() external {
        vm.expectRevert("MerklFacet/zero-distributor");
        vm.prank(admin);
        controller.setDistributor(address(0));
    }

    function test_setDistributor() external {
        address distributor = makeAddr("distributor");

        assertEq(controller.distributor(), address(0));

        vm.record();

        vm.expectEmit(address(controller));
        emit IMerklFacet.MerklDistributorSet(distributor);

        vm.prank(admin);
        controller.setDistributor(distributor);

        assertEq(controller.distributor(), distributor);

        _assertReentrancyGuardWrittenToTwice(address(controller));
    }

}
