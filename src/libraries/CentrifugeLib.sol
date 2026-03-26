// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }        from "../interfaces/IALMProxy.sol";
import { ICentrifugeFacet } from "../interfaces/facets/ICentrifugeFacet.sol";
import { IRateLimits }      from "../interfaces/IRateLimits.sol";

import { makeAddressKey, makeAddressUint16Key } from "../RateLimitHelpers.sol";

import { FacetBase } from "./FacetBase.sol";

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
    /*** CentrifugeFacet Storage Domain                                                         ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CentrifugeFacet
    struct FacetStorage {
        mapping(uint16 centrifugeId => bytes32 recipient) recipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CentrifugeFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xc069081c0c1d07d37b10d4b49109414316895d1a08146dc2106442b9fa4f7900;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant LIMIT_REDEEM   = keccak256("LIMIT_7540_REDEEM");

    // Requests for Centrifuge pools are non-fungible and all have ID = 0.
    uint256 public constant REQUEST_ID = 0;

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function setRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CentrifugeRecipientSet(
            centrifugeId,
            _getFacetStorage().recipients[centrifugeId] = recipient
        );
    }

    function cancelDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        _rateLimitExists($.rateLimits, makeAddressKey(LIMIT_DEPOSIT, token));

        // NOTE: While the cancellation is pending, no new deposit request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelDepositRequest, (REQUEST_ID, proxy))
        );
    }

    function claimCancelDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        _rateLimitExists($.rateLimits, makeAddressKey(LIMIT_DEPOSIT, token));

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelDepositRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );
    }

    function cancelRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        _rateLimitExists($.rateLimits, makeAddressKey(LIMIT_REDEEM, token));

        // NOTE: While the cancellation is pending, no new redeem request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelRedeemRequest, (REQUEST_ID, proxy))
        );
    }

    function claimCancelRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        _rateLimitExists($.rateLimits, makeAddressKey(LIMIT_REDEEM, token));

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelRedeemRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );
    }

    function transferShares(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressUint16Key(LIMIT_TRANSFER, token, centrifugeId),
            amount
        );

        bytes32 recipient = _getFacetStorage().recipients[centrifugeId];

        require(recipient != 0, "CentrifugeFacet/id-not-configured");

        address spoke 
            = IAsyncRedeemManagerLike(ICentrifugeV3VaultLike(token).baseManager()).spoke();

        // Initiate cross-chain transfer via the specific spoke address
        IALMProxy(proxy).doCallWithValue{value: msg.value}(
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
    }

    /**********************************************************************************************/
    /*** Public view/pure functions.                                                            ***/
    /**********************************************************************************************/

    function getRecipient(uint16 centrifugeId) external view returns (bytes32) {
        return _getFacetStorage().recipients[centrifugeId];
    }

    /**********************************************************************************************/
    /*** Internal view/pure functions                                                           ***/
    /**********************************************************************************************/

    function _rateLimitExists(address rateLimits, bytes32 key) internal view {
        require(
            IRateLimits(rateLimits).getRateLimitData(key).maxAmount > 0,
            "CentrifugeFacet/invalid-action"
        );
    }

}
