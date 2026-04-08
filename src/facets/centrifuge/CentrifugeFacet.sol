// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey, makeAddressUint16Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { ICentrifugeFacet } from "./ICentrifugeFacet.sol";

interface IAsyncRedeemManagerLike {

    function spoke() external view returns (address);

}

interface ICentrifugeV3VaultLike {

    function cancelDepositRequest(uint256 requestId, address controller) external;

    function cancelRedeemRequest(uint256 requestId, address controller) external;

    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 assets);

    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 shares);

    function baseManager() external view returns (address);

    function poolId() external view returns (uint64);

    function scId() external view returns (bytes16);

}

interface ISpokeLike {

    function crosschainTransferShares(
        uint16  centrifugeId,
        uint64  poolId,
        bytes16 scId,
        bytes32 receiver,
        uint128 amount,
        uint128 remoteExtraGasLimit
    ) external payable;

}

contract CentrifugeFacet is ICentrifugeFacet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CentrifugeFacet.v1
    struct FacetStorage {
        mapping (uint16 centrifugeId => bytes32 recipient) recipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CentrifugeFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x3b05298d8a8a9ef38d7780d7c82bab887b2a7a923ac41946991c2dd3e283d400;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_TRANSFER = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant override LIMIT_REDEEM   = keccak256("LIMIT_7540_REDEEM");

    // Requests for Centrifuge pools are non-fungible and all have ID = 0.
    uint256 public constant override REQUEST_ID = 0;

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CentrifugeRecipientSet(
            centrifugeId,
            _getFacetStorage().recipients[centrifugeId] = recipient
        );
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function cancelDepositRequest(address token)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _rateLimitExists(makeAddressKey(LIMIT_DEPOSIT, token));

        address proxy = _getSharedControllerStorage().proxy;

        // NOTE: While the cancellation is pending, no new deposit request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelDepositRequest, (REQUEST_ID, proxy))
        );

        emit CentrifugeCancelDepositRequest(token);
    }

    function claimCancelDepositRequest(address token)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _rateLimitExists(makeAddressKey(LIMIT_DEPOSIT, token));

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelDepositRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );

        emit CentrifugeClaimCancelDepositRequest(token);
    }

    function cancelRedeemRequest(address token)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _rateLimitExists(makeAddressKey(LIMIT_REDEEM, token));

        address proxy = _getSharedControllerStorage().proxy;

        // NOTE: While the cancellation is pending, no new redeem request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelRedeemRequest, (REQUEST_ID, proxy))
        );

        emit CentrifugeCancelRedeemRequest(token);
    }

    function claimCancelRedeemRequest(address token)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _rateLimitExists(makeAddressKey(LIMIT_REDEEM, token));

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelRedeemRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );

        emit CentrifugeClaimCancelRedeemRequest(token);
    }

    function transferShares(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressUint16Key(LIMIT_TRANSFER, token, centrifugeId),
            amount
        );

        bytes32 recipient = _getFacetStorage().recipients[centrifugeId];

        require(recipient != 0, "CentrifugeFacet/id-not-configured");

        address spoke
            = IAsyncRedeemManagerLike(ICentrifugeV3VaultLike(token).baseManager()).spoke();

        // Initiate cross-chain transfer via the specific spoke address.
        IALMProxy($.proxy).doCallWithValue{value: msg.value}(
            spoke,
            abi.encodeCall(
                ISpokeLike.crosschainTransferShares,
                (
                    centrifugeId,
                    ICentrifugeV3VaultLike(token).poolId(),
                    ICentrifugeV3VaultLike(token).scId(),
                    recipient,
                    amount,
                    0
                )
            ),
            msg.value
        );

        emit CentrifugeTransferShares(token, amount, centrifugeId);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getRecipient(uint16 centrifugeId) external view override returns (bytes32) {
        return _getFacetStorage().recipients[centrifugeId];
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _rateLimitExists(bytes32 key) internal view {
        require(
            IRateLimits(
                _getSharedControllerStorage().rateLimits
            ).getRateLimitData(key).maxAmount > 0,
            "CentrifugeFacet/invalid-action"
        );
    }

}
