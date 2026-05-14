// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    makeAddressKey,
    makeAddressUint16AddressKey
} from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ICentrifugeFacet } from "./ICentrifugeFacet.sol";

interface IAsyncRedeemManagerLike {

    function spoke() external view returns (address);

}

interface ICentrifugeV3VaultLike {

    function baseManager() external view returns (address);

    function cancelDepositRequest(uint256 requestId, address controller) external;

    function cancelRedeemRequest(uint256 requestId, address controller) external;

    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 assets);

    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 shares);

    function poolId() external view returns (uint64);

    function scId() external view returns (bytes16);

    function share() external view returns (address);

}

interface IERC20Like {

    function balanceOf(address owner) external view returns (uint256);

}

interface IERC4626Like {

    function asset() external view returns (address);

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

contract CentrifugeFacet is ICentrifugeFacet, Facet {

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

    bytes32 internal constant _LIMIT_CANCEL_DEPOSIT = keccak256("LIMIT_CENTRIFUGE_CANCEL_DEPOSIT");

    bytes32 internal constant _LIMIT_CLAIM_CANCEL_DEPOSIT
        = keccak256("LIMIT_CENTRIFUGE_CLAIM_CANCEL_DEPOSIT");

    bytes32 internal constant _LIMIT_CANCEL_REDEEM = keccak256("LIMIT_CENTRIFUGE_CANCEL_REDEEM");

    bytes32 internal constant _LIMIT_CLAIM_CANCEL_REDEEM
        = keccak256("LIMIT_CENTRIFUGE_CLAIM_CANCEL_REDEEM");

    bytes32 internal constant _LIMIT_TRANSFER = keccak256("LIMIT_CENTRIFUGE_TRANSFER");

    // Requests for Centrifuge pools are non-fungible and all have ID = 0.
    /// @inheritdoc ICentrifugeFacet
    uint256 public constant override REQUEST_ID = 0;

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc ICentrifugeFacet
    function setRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(recipient != bytes32(0), "CentrifugeFacet/zero-recipient");

        emit CentrifugeRecipientSet(
            centrifugeId,
            _getFacetStorage().recipients[centrifugeId] = recipient
        );
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc ICentrifugeFacet
    function cancelDepositRequest(address token)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _requireRateLimitExists(getCancelDepositRateLimitKey(token));

        address proxy = _getSharedControllerStorage().proxy;

        // NOTE: While the cancellation is pending, no new deposit request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelDepositRequest, (REQUEST_ID, proxy))
        );

        emit CentrifugeCancelDepositRequest(token);
    }

    /// @inheritdoc ICentrifugeFacet
    function claimCancelDepositRequest(address token)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _requireRateLimitExists(getClaimCancelDepositRateLimitKey(token));

        address asset = IERC4626Like(token).asset();
        address proxy = _getSharedControllerStorage().proxy;

        uint256 balanceBefore = IERC20Like(asset).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelDepositRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );

        uint256 balanceAfter = IERC20Like(asset).balanceOf(proxy);

        emit CentrifugeClaimCancelDepositRequest(token, balanceAfter - balanceBefore);
    }

    /// @inheritdoc ICentrifugeFacet
    function cancelRedeemRequest(address token)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _requireRateLimitExists(getCancelRedeemRateLimitKey(token));

        address proxy = _getSharedControllerStorage().proxy;

        // NOTE: While the cancellation is pending, no new redeem request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelRedeemRequest, (REQUEST_ID, proxy))
        );

        emit CentrifugeCancelRedeemRequest(token);
    }

    /// @inheritdoc ICentrifugeFacet
    function claimCancelRedeemRequest(address token)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _requireRateLimitExists(getClaimCancelRedeemRateLimitKey(token));

        address proxy = _getSharedControllerStorage().proxy;
        address share = ICentrifugeV3VaultLike(token).share();

        uint256 balanceBefore = IERC20Like(share).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelRedeemRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );

        uint256 balanceAfter = IERC20Like(share).balanceOf(proxy);

        emit CentrifugeClaimCancelRedeemRequest(token, balanceAfter - balanceBefore);
    }

    /// @inheritdoc ICentrifugeFacet
    function transferShares(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        bytes32 recipient = _getFacetStorage().recipients[centrifugeId];

        require(recipient != 0, "CentrifugeFacet/id-not-configured");

        address spoke
            = IAsyncRedeemManagerLike(ICentrifugeV3VaultLike(token).baseManager()).spoke();

        // NOTE: Trusting that the amount transferred by the spoke call is the same as requested.
        _decreaseRateLimit(getTransferRateLimitKey(token, centrifugeId, spoke), amount);

        // Initiate cross-chain transfer via the specific spoke address.
        IALMProxy(_getSharedControllerStorage().proxy).doCallWithValue{value: msg.value}(
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

    /// @inheritdoc ICentrifugeFacet
    function getRecipient(uint16 centrifugeId) external view override returns (bytes32) {
        return _getFacetStorage().recipients[centrifugeId];
    }

    /// @inheritdoc ICentrifugeFacet
    function getCancelDepositRateLimitKey(address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressKey(_LIMIT_CANCEL_DEPOSIT, token);
    }

    /// @inheritdoc ICentrifugeFacet
    function getClaimCancelDepositRateLimitKey(address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressKey(_LIMIT_CLAIM_CANCEL_DEPOSIT, token);
    }

    /// @inheritdoc ICentrifugeFacet
    function getCancelRedeemRateLimitKey(address token) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_CANCEL_REDEEM, token);
    }

    /// @inheritdoc ICentrifugeFacet
    function getClaimCancelRedeemRateLimitKey(address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressKey(_LIMIT_CLAIM_CANCEL_REDEEM, token);
    }

    /// @inheritdoc ICentrifugeFacet
    function getTransferRateLimitKey(address token, uint16 centrifugeId, address spoke)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressUint16AddressKey(_LIMIT_TRANSFER, token, centrifugeId, spoke);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _requireRateLimitExists(bytes32 key) internal view {
        require(_rateLimitExists(key), "CentrifugeFacet/invalid-action");
    }

}
