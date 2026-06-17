// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IFacet }                  from "../../../src/facets/IFacet.sol";
import { INFATHaloFacet }          from "../../../src/facets/nfat-halo/INFATHaloFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { makeAddressAddressKey } from "../../../src/libraries/RateLimitHelpers.sol";

import { NFATHaloFacet } from "../../../src/facets/nfat-halo/NFATHaloFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setMaxAnnualGrowthRate(address facility, uint256 maxAnnualGrowthRate) external;

    function getMaxAnnualGrowthRate(address facility) external view returns (uint256);

    function getFacilityState(address facility)
        external
        view
        returns (uint256 interestIndex, uint256 lastUpdated);

    function getIssueRateLimitKey(address facility, address to) external pure returns (bytes32);

    function getRepayInterestRateLimitKey(address facility, address gem) external pure returns (bytes32);

    function getRepayPrincipalRateLimitKey(address facility, address gem) external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_NFATHaloFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    uint256 internal constant MAX_ANNUAL_GROWTH_RATE = 0.20e18;  // 20% APR
    uint256 internal constant TOKEN_ID               = 1;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new NFATHaloFacet());

        vm.label(facet, "NFATHaloFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setMaxAnnualGrowthRate.selector,
            INFATHaloFacet.setMaxAnnualGrowthRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.getMaxAnnualGrowthRate.selector,
            INFATHaloFacet.getMaxAnnualGrowthRate.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.getFacilityState.selector,
            INFATHaloFacet.getFacilityState.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.getIssueRateLimitKey.selector,
            INFATHaloFacet.getIssueRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.getRepayInterestRateLimitKey.selector,
            INFATHaloFacet.getRepayInterestRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.getRepayPrincipalRateLimitKey.selector,
            INFATHaloFacet.getRepayPrincipalRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("NFAT_HALO_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "NFAT_HALO_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** setMaxAnnualGrowthRate Tests                                                           ***/
    /**********************************************************************************************/

    function test_setMaxAnnualGrowthRate_reentrancy() external {
        _setEntered(address(controller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        controller.setMaxAnnualGrowthRate(makeAddr("facility"), MAX_ANNUAL_GROWTH_RATE);
    }

    function test_setMaxAnnualGrowthRate_notAdmin() external {
        address facility = makeAddr("facility");

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(unauthorized);
        controller.setMaxAnnualGrowthRate(facility, MAX_ANNUAL_GROWTH_RATE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFacet.AccessControlUnauthorizedAccount.selector,
                allocator,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(allocator);
        controller.setMaxAnnualGrowthRate(facility, MAX_ANNUAL_GROWTH_RATE);
    }

    function test_setMaxAnnualGrowthRate_zeroFacility() external {
        vm.expectRevert("NFATHaloFacet/facility-zero-address");
        vm.prank(admin);
        controller.setMaxAnnualGrowthRate(address(0), MAX_ANNUAL_GROWTH_RATE);
    }

    function test_setMaxAnnualGrowthRate() external {
        address facility       = makeAddr("facility");
        uint256 startTimestamp = vm.getBlockTimestamp();

        vm.expectEmit(address(controller));
        emit INFATHaloFacet.NFATHaloMaxAnnualGrowthRateSet(facility, MAX_ANNUAL_GROWTH_RATE);

        vm.record();

        vm.prank(admin);
        controller.setMaxAnnualGrowthRate(facility, MAX_ANNUAL_GROWTH_RATE);

        _assertReentrancyGuardWrittenToTwice(address(controller));

        assertEq(controller.getMaxAnnualGrowthRate(facility), MAX_ANNUAL_GROWTH_RATE);

        ( uint256 interestIndex, uint256 lastUpdated ) = controller.getFacilityState(facility);

        assertEq(interestIndex, 0);
        assertEq(lastUpdated,   startTimestamp);

        vm.warp(startTimestamp + 180 days);

        uint256 newRate = 0.50e18;

        vm.expectEmit(address(controller));
        emit INFATHaloFacet.NFATHaloMaxAnnualGrowthRateSet(facility, newRate);

        vm.prank(admin);
        controller.setMaxAnnualGrowthRate(facility, newRate);

        assertEq(controller.getMaxAnnualGrowthRate(facility), newRate);

        ( interestIndex, lastUpdated ) = controller.getFacilityState(facility);

        assertEq(interestIndex, 0.098630136986301369e18);
        assertEq(lastUpdated,   vm.getBlockTimestamp());
    }

    /**********************************************************************************************/
    /*** getIssueRateLimitKey Tests                                                             ***/
    /**********************************************************************************************/

    function test_getIssueRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_HALO_ISSUE");
        address facility  = makeAddr("facility");
        address to        = makeAddr("to");

        assertEq(
            controller.getIssueRateLimitKey(facility, to),
            makeAddressAddressKey(keyPrefix, facility, to)
        );
    }

    /**********************************************************************************************/
    /*** getRepayInterestRateLimitKey Tests                                                     ***/
    /**********************************************************************************************/

    function test_getRepayInterestRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_HALO_REPAY_INTEREST");
        address facility  = makeAddr("facility");
        address gem       = makeAddr("gem");

        assertEq(
            controller.getRepayInterestRateLimitKey(facility, gem),
            makeAddressAddressKey(keyPrefix, gem, facility)
        );
    }

    /**********************************************************************************************/
    /*** getRepayPrincipalRateLimitKey Tests                                                    ***/
    /**********************************************************************************************/

    function test_getRepayPrincipalRateLimitKey() external {
        bytes32 keyPrefix = keccak256("LIMIT_NFAT_HALO_REPAY_PRINCIPAL");
        address facility  = makeAddr("facility");
        address gem       = makeAddr("gem");

        assertEq(
            controller.getRepayPrincipalRateLimitKey(facility, gem),
            makeAddressAddressKey(keyPrefix, gem, facility)
        );
    }

}
