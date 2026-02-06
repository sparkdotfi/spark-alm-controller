// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    OptionsBuilder
} from "../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import {
    ILayerZeroLike,
    SendParam,
    OFTReceipt,
    MessagingFee,
    OFTLimit,
    OFTFeeDetail
} from "../interfaces/ILayerZero.sol";

import { makeAddressUint32Key } from "../RateLimitHelpers.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

import { ApproveLib } from "./ApproveLib.sol";

library LayerZeroLib {

    using OptionsBuilder for bytes;

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_TRANSFER");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setLayerZeroRecipient(
        mapping(uint32 => bytes32) storage layerZeroRecipients,
        uint32                             destinationEndpointId,
        bytes32                            recipient
    )
        external
    {
        layerZeroRecipients[destinationEndpointId] = recipient;
        emit LayerZeroRecipientSet(destinationEndpointId, recipient);
    }

    function transferTokenLayerZero(
        address                            proxy,
        address                            rateLimits,
        address                            oftAddress,
        uint256                            amount,
        uint32                             destinationEndpointId,
        mapping(uint32 => bytes32) storage layerZeroRecipients
    ) external {
        _decreaseRateLimit(rateLimits, LIMIT_TRANSFER, oftAddress, destinationEndpointId, amount);

        bytes32 recipient = layerZeroRecipients[destinationEndpointId];

        require(recipient != bytes32(0), "LayerZeroLib/recipient-not-set");

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZeroLike(oftAddress).approvalRequired()) {
            ApproveLib.approve(
                ILayerZeroLike(oftAddress).token(),
                proxy,
                oftAddress,
                amount
            );
        }

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : recipient,
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( , , OFTReceipt memory receipt ) = abi.decode(
            IALMProxy(proxy).doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteOFT, (sendParams))
            ),
            (OFTLimit, OFTFeeDetail[], OFTReceipt)
        );

        sendParams.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = ILayerZeroLike(oftAddress).quoteSend(sendParams, false);

        IALMProxy(proxy).doCallWithValue{value: fee.nativeFee}(
            oftAddress,
            abi.encodeCall(ILayerZeroLike.send, (sendParams, fee, proxy)),
            fee.nativeFee
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(
        address rateLimits,
        bytes32 key,
        address oftAddress,
        uint32  destinationEndpointId,
        uint256 amount
    ) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressUint32Key(key, oftAddress, destinationEndpointId),
            amount
        );
    }

}
