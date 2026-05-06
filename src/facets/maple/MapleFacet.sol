// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IMapleFacet } from "./IMapleFacet.sol";

interface IMapleTokenLike {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

}

contract MapleFacet is IMapleFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_REQUEST_REDEEM = keccak256("LIMIT_MAPLE_REQUEST_REDEEM");
    bytes32 internal constant _LIMIT_CANCEL_REDEEM  = keccak256("LIMIT_MAPLE_CANCEL_REDEEM");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IMapleFacet
    function requestRedemption(address mapleToken, uint256 shares)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(
            getRequestRedeemRateLimitKey(mapleToken),
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        );

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.requestRedeem, (shares, proxy))
        );

        emit MapleRequestRedemption(mapleToken, shares);
    }

    /// @inheritdoc IMapleFacet
    function cancelRedemption(address mapleToken, uint256 shares)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(
            _rateLimitExists(getCancelRedeemRateLimitKey(mapleToken)),
            "MapleFacet/invalid-action"
        );

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.removeShares, (shares, proxy))
        );

        emit MapleCancelRedemption(mapleToken, shares);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IMapleFacet
    function getRequestRedeemRateLimitKey(address mapleToken) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_REQUEST_REDEEM, mapleToken);
    }

    /// @inheritdoc IMapleFacet
    function getCancelRedeemRateLimitKey(address mapleToken) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_CANCEL_REDEEM, mapleToken);
    }

}
