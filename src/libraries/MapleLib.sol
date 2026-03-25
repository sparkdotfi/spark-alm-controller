// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IMapleFacet } from "../interfaces/facets/IMapleFacet.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { FacetBase } from "./FacetBase.sol";

interface IMapleTokenLike is IERC4626 {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

}

contract MapleFacet is IMapleFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_REDEEM = keccak256("LIMIT_MAPLE_REDEEM");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function requestRedemption(address mapleToken, uint256 shares)
        external
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
