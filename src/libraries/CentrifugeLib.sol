// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import {
    ICentrifugeV3VaultLike,
    IAsyncRedeemManagerLike,
    ISpokeLike
} from "../interfaces/CentrifugeInterfaces.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library CentrifugeLib {

    struct CentrifugeRequestParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     token;
        bytes32     rateLimitId;
        uint256     requestId;
    }

    struct CentrifugeTransferParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     token;
        uint16      destinationCentrifugeId;
        uint128     amount;
        bytes32     recipient;
        bytes32     rateLimitId;
    }

    function cancelCentrifugeDepositRequest(CentrifugeRequestParams memory params) external {
        _rateLimitExists(params.rateLimits, RateLimitHelpers.makeAssetKey(params.rateLimitId, params.token));

        // NOTE: While the cancelation is pending, no new deposit request can be submitted
        params.proxy.doCall(
            params.token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(params.token).cancelDepositRequest,
                (params.requestId, address(params.proxy))
            )
        );
    }

    function claimCentrifugeCancelDepositRequest(CentrifugeRequestParams memory params) external {
        _rateLimitExists(params.rateLimits, RateLimitHelpers.makeAssetKey(params.rateLimitId, params.token));

        params.proxy.doCall(
            params.token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(params.token).claimCancelDepositRequest,
                (params.requestId, address(params.proxy), address(params.proxy))
            )
        );
    }

    function cancelCentrifugeRedeemRequest(CentrifugeRequestParams memory params) external {
        _rateLimitExists(params.rateLimits, RateLimitHelpers.makeAssetKey(params.rateLimitId, params.token));

        // NOTE: While the cancelation is pending, no new redeem request can be submitted
        params.proxy.doCall(
            params.token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(params.token).cancelRedeemRequest,
                (params.requestId, address(params.proxy))
            )
        );
    }

    function claimCentrifugeCancelRedeemRequest(CentrifugeRequestParams memory params) external {
        _rateLimitExists(params.rateLimits, RateLimitHelpers.makeAssetKey(params.rateLimitId, params.token));

        params.proxy.doCall(
            params.token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(params.token).claimCancelRedeemRequest,
                (params.requestId, address(params.proxy), address(params.proxy))
            )
        );
    }

    function transferSharesCentrifuge(CentrifugeTransferParams memory params) external {
        _rateLimited(
            params.rateLimits,
            keccak256(abi.encode(params.rateLimitId, params.token, params.destinationCentrifugeId)),
            params.amount
        );

        require(params.recipient != 0, "MainnetController/centrifuge-id-not-configured");

        ICentrifugeV3VaultLike centrifugeVault = ICentrifugeV3VaultLike(params.token);

        address spoke = IAsyncRedeemManagerLike(centrifugeVault.manager()).spoke();

        // Initiate cross-chain transfer via the specific spoke address
        params.proxy.doCallWithValue{value: msg.value}(
            spoke,
            abi.encodeCall(
                ISpokeLike(spoke).crosschainTransferShares,
                (
                    params.destinationCentrifugeId,
                    centrifugeVault.poolId(),
                    centrifugeVault.scId(),
                    params.recipient,
                    params.amount,
                    0
                )
            ),
            msg.value
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

    function _rateLimitExists(IRateLimits rateLimits, bytes32 key) internal view {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "MainnetController/invalid-action"
        );
    }
}
