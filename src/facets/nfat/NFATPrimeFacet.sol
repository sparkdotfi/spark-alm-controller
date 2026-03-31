// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { INFATPrimeFacet } from "./INFATPrimeFacet.sol";

interface INFATFacilityLike {

    function gem() external view returns (address);

    function subscribe(uint256 amount, bytes calldata data) external;

    function withdraw(uint256 amount) external;

    function collect(uint256 tokenId, uint256 amount) external;

}

contract NFATPrimeFacet is INFATPrimeFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_SUBSCRIBE = keccak256("LIMIT_NFAT_SUBSCRIBE");
    bytes32 public constant LIMIT_COLLECT   = keccak256("LIMIT_NFAT_COLLECT");

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function subscribe(address nfatFacility, uint256 amount, bytes calldata data)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_SUBSCRIBE, nfatFacility),
            amount
        );

        address proxy = $.proxy;

        ApproveLib.approve(INFATFacilityLike(nfatFacility).gem(), proxy, nfatFacility, amount);

        IALMProxy(proxy).doCall(
            nfatFacility,
            abi.encodeCall(INFATFacilityLike.subscribe, (amount, data))
        );
    }

    // NOTE: withdraw() cancels queued deposits before issuance. Since the funds have not yet been
    // deployed into an issued NFAT position, this path refills LIMIT_SUBSCRIBE on exit, mirroring
    // facets such as ERC4626 and Aave where returned capital restores deposit capacity. No separate
    // withdraw limit is used here because this action only returns unsubscribed capital.
    function withdraw(address nfatFacility, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IALMProxy($.proxy).doCall(
            nfatFacility,
            abi.encodeCall(INFATFacilityLike.withdraw, (amount))
        );

        IRateLimits($.rateLimits).triggerRateLimitIncrease(
            makeAddressKey(LIMIT_SUBSCRIBE, nfatFacility),
            amount
        );
    }

    // NOTE: collect() returns repaid funds from an issued NFAT position back to the proxy.
    // LIMIT_COLLECT bounds the rate at which funds can be pulled from a facility, consistent with
    // the repo's broader pattern of rate-limiting return flows from external systems. Because the
    // collected funds are back on the proxy and available for redeployment, this path also refills
    // LIMIT_SUBSCRIBE.
    function collect(address nfatFacility, uint256 tokenId, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits rateLimits = IRateLimits($.rateLimits);

        rateLimits.triggerRateLimitDecrease(
            makeAddressKey(LIMIT_COLLECT, nfatFacility),
            amount
        );

        IALMProxy($.proxy).doCall(
            nfatFacility,
            abi.encodeCall(INFATFacilityLike.collect, (tokenId, amount))
        );

        rateLimits.triggerRateLimitIncrease(
            makeAddressKey(LIMIT_SUBSCRIBE, nfatFacility),
            amount
        );
    }

}
