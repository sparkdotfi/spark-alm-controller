// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { INFATHaloFacet } from "./INFATHaloFacet.sol";

interface INFATFacilityLike {

    function gem() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function repay(uint256 tokenId, uint256 amount) external;

}

contract NFATHaloFacet is INFATHaloFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_REPAY = keccak256("LIMIT_NFAT_REPAY");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function repay(address nfatFacility, uint256 tokenId, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(
                LIMIT_REPAY,
                nfatFacility,
                INFATFacilityLike(nfatFacility).ownerOf(tokenId)
            ),
            amount
        );

        address proxy = $.proxy;

        ApproveLib.approve(INFATFacilityLike(nfatFacility).gem(), proxy, nfatFacility, amount);

        IALMProxy(proxy).doCall(
            nfatFacility,
            abi.encodeCall(INFATFacilityLike.repay, (tokenId, amount))
        );
    }

}
