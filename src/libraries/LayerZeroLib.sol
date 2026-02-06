// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    ILayerZeroLike,
    SendParam,
    OFTReceipt,
    MessagingFee,
    OFTLimit,
    OFTFeeDetail
} from "../interfaces/ILayerZero.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

import { ApproveLib } from "./ApproveLib.sol";

import {
    OptionsBuilder
} from "../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

library LayerZeroLib {

    using OptionsBuilder for bytes;

    bytes32 public constant LIMIT_LAYERZERO_TRANSFER = keccak256("LIMIT_LAYERZERO_TRANSFER");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transferTokenLayerZero(
        IALMProxy   proxy,
        IRateLimits rateLimits,
        address     oftAddress,
        uint256     amount,
        uint32      destinationEndpointId,
        bytes32     layerZeroRecipient
    )
        external
    {
        _rateLimited(
            rateLimits,
            keccak256(
                abi.encode(
                    LIMIT_LAYERZERO_TRANSFER,
                    oftAddress,
                    destinationEndpointId
                )
            ),
            amount
        );

        require(layerZeroRecipient != bytes32(0), "LayerZeroLib/recipient-not-set");

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZeroLike(oftAddress).approvalRequired()) {
            ApproveLib.approve(
                ILayerZeroLike(oftAddress).token(),
                address(proxy),
                oftAddress,
                amount
            );
        }

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : layerZeroRecipient,
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( ,, OFTReceipt memory receipt ) = abi.decode(
            proxy.doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteOFT, (sendParams))
            ),
            (OFTLimit, OFTFeeDetail[], OFTReceipt)
        );

        sendParams.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = ILayerZeroLike(oftAddress).quoteSend(sendParams, false);

        proxy.doCallWithValue{value: fee.nativeFee}(
            oftAddress,
            abi.encodeCall(ILayerZeroLike.send, (sendParams, fee, address(proxy))),
            fee.nativeFee
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
