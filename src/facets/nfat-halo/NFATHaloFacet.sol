// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { INFATHaloFacet } from "./INFATHaloFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IFacilityLike {

    function gem() external view returns (address);

    function issue(address to, uint256 tokenId, uint256 amount) external;

    function repay(uint256 tokenId, uint256 amount) external;

}

contract NFATHaloFacet is INFATHaloFacet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.NFATHaloFacet.v1
    struct FacetStorage {
        mapping (address facility => Parameters params)                         parameters;
        mapping (address facility => FacilityState state)                       states;
        mapping (address facility => mapping (uint256 tokenId => Position pos)) positions;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.NFATHaloFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x9374587c30f7383b766c0ada49451c0a4d8cea55cebbd6eec5b0112712b60800;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_ISSUE           = keccak256("LIMIT_NFAT_HALO_ISSUE");
    bytes32 internal constant _LIMIT_REPAY_PRINCIPAL = keccak256("LIMIT_NFAT_HALO_REPAY_PRINCIPAL");
    bytes32 internal constant _LIMIT_REPAY_INTEREST  = keccak256("LIMIT_NFAT_HALO_REPAY_INTEREST");

    uint256 internal constant _INTEREST_RATE_PRECISION = 1e18;
    uint256 internal constant _YEAR                    = 365 days;

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc INFATHaloFacet
    function setAnnualGrowthRate(address facility, uint256 annualGrowthRate)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(facility != address(0), "NFATHaloFacet/facility-zero-address");

        _checkpointFacility(facility);

        _getFacetStorage().parameters[facility].annualGrowthRate = annualGrowthRate;

        emit NFATHaloAnnualGrowthRateSet(facility, annualGrowthRate);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc INFATHaloFacet
    function issue(address facility, address to, uint256 tokenId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(amount != 0, "NFATHaloFacet/zero-amount");

        _checkpointFacility(facility);

        address proxy = _getSharedControllerStorage().proxy;
        address gem   = IFacilityLike(facility).gem();

        FacetStorage storage $        = _getFacetStorage();
        Position     storage position = $.positions[facility][tokenId];

        require(!position.issued, "NFATHaloFacet/position-exists");

        uint256 startingBalance = IERC20Like(gem).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            facility,
            abi.encodeCall(IFacilityLike.issue, (to, tokenId, amount))
        );

        uint256 received = IERC20Like(gem).balanceOf(proxy) - startingBalance;

        position.issued               = true;
        position.outstandingPrincipal = received;
        position.interestIndex        = $.states[facility].interestIndex;

        _decreaseRateLimit(getIssueRateLimitKey(facility, to), received);

        emit NFATHaloIssue(facility, to, tokenId, received);
    }

    /// @inheritdoc INFATHaloFacet
    function repayPrincipal(address facility, uint256 tokenId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(amount != 0, "NFATHaloFacet/zero-amount");

        Position storage position = _checkpointPosition(facility, tokenId);

        require(amount <= position.outstandingPrincipal, "NFATHaloFacet/principal-exceeded");

        address gem = IFacilityLike(facility).gem();

        uint256 spent = _doFacilityRepay(facility, gem, tokenId, amount);

        position.outstandingPrincipal -= spent;

        _decreaseRateLimit(getRepayPrincipalRateLimitKey(facility, gem), spent);

        emit NFATHaloRepayPrincipal(facility, tokenId, spent);
    }

    /// @inheritdoc INFATHaloFacet
    function repayInterest(address facility, uint256 tokenId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(amount != 0, "NFATHaloFacet/zero-amount");

        Position storage position = _checkpointPosition(facility, tokenId);

        require(amount <= position.outstandingInterest, "NFATHaloFacet/interest-exceeded");

        address gem = IFacilityLike(facility).gem();

        uint256 spent = _doFacilityRepay(facility, gem, tokenId, amount);

        position.outstandingInterest -= spent;

        _decreaseRateLimit(getRepayInterestRateLimitKey(facility, gem), spent);

        emit NFATHaloRepayInterest(facility, tokenId, spent);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc INFATHaloFacet
    function getAnnualGrowthRate(address facility) external view override returns (uint256) {
        return _getFacetStorage().parameters[facility].annualGrowthRate;
    }

    /// @inheritdoc INFATHaloFacet
    function getFacilityState(address facility)
        external
        view
        override
        returns (uint256 interestIndex, uint256 lastUpdated)
    {
        FacilityState storage state = _getFacetStorage().states[facility];
        return (state.interestIndex, state.lastUpdated);
    }

    /// @inheritdoc INFATHaloFacet
    function getPosition(address facility, uint256 tokenId)
        external
        view
        override
        returns (
            bool    issued,
            uint256 outstandingPrincipal,
            uint256 outstandingInterest,
            uint256 interestIndex
        )
    {
        Position storage position = _getFacetStorage().positions[facility][tokenId];

        return (
            position.issued,
            position.outstandingPrincipal,
            position.outstandingInterest,
            position.interestIndex
        );
    }

    /// @inheritdoc INFATHaloFacet
    function getCurrentOutstandingInterest(address facility, uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        Position storage position = _getFacetStorage().positions[facility][tokenId];

        require(position.issued, "NFATHaloFacet/position-not-found");

        uint256 currentIndex = _getCurrentInterestIndex(facility);
        uint256 deltaIndex   = currentIndex - position.interestIndex;

        return
            position.outstandingInterest +
            position.outstandingPrincipal * deltaIndex / _INTEREST_RATE_PRECISION;
    }

    /// @inheritdoc INFATHaloFacet
    function getIssueRateLimitKey(address facility, address to)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_ISSUE, facility, to);
    }

    /// @inheritdoc INFATHaloFacet
    function getRepayInterestRateLimitKey(address facility, address gem)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_REPAY_INTEREST, gem, facility);
    }

    /// @inheritdoc INFATHaloFacet
    function getRepayPrincipalRateLimitKey(address facility, address gem)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_REPAY_PRINCIPAL, gem, facility);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _checkpointFacility(address facility) internal {
        FacilityState storage state = _getFacetStorage().states[facility];

        uint256 lastUpdated = state.lastUpdated;

        if (lastUpdated == block.timestamp) return;

        state.interestIndex = _getCurrentInterestIndex(facility);
        state.lastUpdated   = block.timestamp;
    }

    function _checkpointPosition(address facility, uint256 tokenId)
        internal
        returns (Position storage position)
    {
        _checkpointFacility(facility);

        FacetStorage storage $ = _getFacetStorage();

        position = $.positions[facility][tokenId];

        require(position.issued, "NFATHaloFacet/position-not-found");

        uint256 currentIndex = $.states[facility].interestIndex;

        position.outstandingInterest +=
            position.outstandingPrincipal * (currentIndex - position.interestIndex)
            / _INTEREST_RATE_PRECISION;

        position.interestIndex = currentIndex;
    }

    function _doFacilityRepay(address facility, address gem, uint256 tokenId, uint256 amount)
        internal
        returns (uint256 spent)
    {
        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(gem, proxy, facility, amount);

        uint256 startingBalance = IERC20Like(gem).balanceOf(proxy);

        IALMProxy(proxy).doCall(facility, abi.encodeCall(IFacilityLike.repay, (tokenId, amount)));

        ApproveLib.approve(gem, proxy, facility, 0);

        spent = startingBalance - IERC20Like(gem).balanceOf(proxy);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getCurrentInterestIndex(address facility) internal view returns (uint256) {
        FacetStorage  storage $     = _getFacetStorage();
        FacilityState storage state = $.states[facility];

        uint256 lastUpdated = state.lastUpdated;

        if (lastUpdated == 0) return state.interestIndex;

        return
            state.interestIndex +
            $.parameters[facility].annualGrowthRate * (block.timestamp - lastUpdated) / _YEAR;
    }

}
