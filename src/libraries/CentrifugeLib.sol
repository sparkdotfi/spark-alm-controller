// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey, makeAddressUint16Key } from "../RateLimitHelpers.sol";

import { ERC7540Lib } from "./ERC7540Lib.sol";

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

library CentrifugeLib {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CentrifugeRecipientSet(uint16 indexed centrifugeId, bytes32 indexed recipient);

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
    bytes32 public constant LIMIT_DEPOSIT  = ERC7540Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_REDEEM   = ERC7540Lib.LIMIT_REDEEM;

    // Requests for Centrifuge pools are non-fungible and all have ID = 0.
    uint256 public constant REQUEST_ID = 0;

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function setCentrifugeRecipient(
        mapping (uint16 centrifugeId => bytes32 recipient) storage recipients,
        uint16  centrifugeId,
        bytes32 recipient
    ) external {
        emit CentrifugeRecipientSet(centrifugeId, recipients[centrifugeId] = recipient);
    }

    function cancelDepositRequest(address proxy, address rateLimits, address token) external {
        _rateLimitExists(IRateLimits(rateLimits), makeAddressKey(LIMIT_DEPOSIT, token));

        // NOTE: While the cancellation is pending, no new deposit request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelDepositRequest, (REQUEST_ID, proxy))
        );
    }

    function claimCancelDepositRequest(address proxy, address rateLimits, address token) external {
        _rateLimitExists(IRateLimits(rateLimits), makeAddressKey(LIMIT_DEPOSIT, token));

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelDepositRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );
    }

    function cancelRedeemRequest(address proxy, address rateLimits, address token) external {
        _rateLimitExists(IRateLimits(rateLimits), makeAddressKey(LIMIT_REDEEM, token));

        // NOTE: While the cancellation is pending, no new redeem request can be submitted.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(ICentrifugeV3VaultLike(token).cancelRedeemRequest, (REQUEST_ID, proxy))
        );
    }

    function claimCancelRedeemRequest(address proxy, address rateLimits, address token) external {
        _rateLimitExists(IRateLimits(rateLimits), makeAddressKey(LIMIT_REDEEM, token));

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelRedeemRequest,
                (REQUEST_ID, proxy, proxy)
            )
        );
    }

    function transferShares(
        address proxy,
        address rateLimits,
        address token,
        uint16  centrifugeId,
        uint128 amount,
        mapping (uint16 centrifugeId => bytes32 recipient) storage recipients
    ) external {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressUint16Key(LIMIT_TRANSFER, token, centrifugeId),
            amount
        );

        bytes32 recipient = recipients[centrifugeId];

        require(recipient != 0, "CentrifugeLib/id-not-configured");

        address spoke = IAsyncRedeemManagerLike(ICentrifugeV3VaultLike(token).baseManager()).spoke();

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
    /*** Internal view/pure functions                                                           ***/
    /**********************************************************************************************/

    function _rateLimitExists(IRateLimits rateLimits, bytes32 key) internal view {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "CentrifugeLib/invalid-action"
        );
    }

}
