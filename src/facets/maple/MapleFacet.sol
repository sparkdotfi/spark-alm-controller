// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IMapleFacet } from "./IMapleFacet.sol";

interface IMapleTokenLike {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

}

contract MapleFacet is IMapleFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_REDEEM = keccak256("LIMIT_MAPLE_REDEEM");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function requestRedemption(address mapleToken, uint256 shares)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REDEEM, mapleToken),
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        );

        address proxy = $.proxy;

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.requestRedeem, (shares, proxy))
        );
    }

    function cancelRedemption(address mapleToken, uint256 shares)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        require(
            IRateLimits($.rateLimits).getRateLimitData(
                makeAddressKey(LIMIT_REDEEM, mapleToken)
            ).maxAmount > 0,
            "MapleFacet/invalid-action"
        );

        address proxy = $.proxy;

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.removeShares, (shares, proxy))
        );
    }

}
