// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { INFATPrimeFacet } from "./INFATPrimeFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IFacilityLike {

    function gem() external view returns (address);

    function subscribe(uint256 amount, bytes calldata data) external;

    function withdraw(uint256 amount) external;

    function collect(uint256 tokenId, uint256 amount) external;

}

contract NFATPrimeFacet is INFATPrimeFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_SUBSCRIBE = keccak256("LIMIT_NFAT_PRIME_SUBSCRIBE");
    bytes32 internal constant _LIMIT_WITHDRAW  = keccak256("LIMIT_NFAT_PRIME_WITHDRAW");
    bytes32 internal constant _LIMIT_COLLECT   = keccak256("LIMIT_NFAT_PRIME_COLLECT");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc INFATPrimeFacet
    function subscribe(address facility, uint256 amount, bytes calldata data)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        address proxy = _getSharedControllerStorage().proxy;
        address gem   = IFacilityLike(facility).gem();

        ApproveLib.approve(gem, proxy, facility, amount);

        uint256 startingBalance = IERC20Like(gem).balanceOf(proxy);

        IALMProxy(proxy).doCall(facility, abi.encodeCall(IFacilityLike.subscribe, (amount, data)));

        ApproveLib.approve(gem, proxy, facility, 0);

        uint256 spent = startingBalance - IERC20Like(gem).balanceOf(proxy);

        _decreaseRateLimit(getSubscribeRateLimitKey(facility, gem), spent);

        emit NFATPrimeSubscribe(facility, spent, data);
    }

    /// @inheritdoc INFATPrimeFacet
    function withdraw(address facility, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(amount != 0, "NFATPrimeFacet/zero-amount");

        address proxy = _getSharedControllerStorage().proxy;
        address gem   = IFacilityLike(facility).gem();

        uint256 startingBalance = IERC20Like(gem).balanceOf(proxy);

        IALMProxy(proxy).doCall(facility, abi.encodeCall(IFacilityLike.withdraw, (amount)));

        uint256 received = IERC20Like(gem).balanceOf(proxy) - startingBalance;

        _decreaseRateLimit(getWithdrawRateLimitKey(facility), received);

        emit NFATPrimeWithdraw(facility, received);
    }

    /// @inheritdoc INFATPrimeFacet
    function collect(address facility, uint256 tokenId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(amount != 0, "NFATPrimeFacet/zero-amount");

        address proxy = _getSharedControllerStorage().proxy;
        address gem   = IFacilityLike(facility).gem();

        uint256 startingBalance = IERC20Like(gem).balanceOf(proxy);

        IALMProxy(proxy).doCall(facility, abi.encodeCall(IFacilityLike.collect, (tokenId, amount)));

        uint256 received = IERC20Like(gem).balanceOf(proxy) - startingBalance;

        _decreaseRateLimit(getCollectRateLimitKey(facility), received);

        emit NFATPrimeCollect(facility, tokenId, received);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc INFATPrimeFacet
    function getSubscribeRateLimitKey(address facility, address gem)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_SUBSCRIBE, gem, facility);
    }

    /// @inheritdoc INFATPrimeFacet
    function getWithdrawRateLimitKey(address facility) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_WITHDRAW, facility);
    }

    /// @inheritdoc INFATPrimeFacet
    function getCollectRateLimitKey(address facility) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_COLLECT, facility);
    }

}
