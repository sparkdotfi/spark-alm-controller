// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ILayerZero, SendParam, OFTReceipt, MessagingFee } from "../interfaces/ILayerZero.sol";
import { IRateLimits }                                     from "../interfaces/IRateLimits.sol";
import { IALMProxy }                                       from "../interfaces/IALMProxy.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

library LzLib {

    using OptionsBuilder for bytes;
    
    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct TransferTokenLayerZeroParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     oftAddress;
        uint256     amount;
        uint32      destinationEndpointId;
        bytes32     rateLimitId;
        bytes32     layerZeroRecipient;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transferTokenLayerZero(TransferTokenLayerZeroParams calldata params) external {
        _rateLimited(
            params.rateLimits,
            keccak256(abi.encode(params.rateLimitId, params.oftAddress, params.destinationEndpointId)),
            params.amount
        );

        require(params.layerZeroRecipient != bytes32(0), "MC/recipient-not-set");

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZero(params.oftAddress).approvalRequired()) {
            ApproveLib.approve(
                ILayerZero(params.oftAddress).token(),
                address(params.proxy),
                params.oftAddress,
                params.amount
            );
        }

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : params.destinationEndpointId,
            to           : params.layerZeroRecipient,
            amountLD     : params.amount,
            minAmountLD  : 0,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( , , OFTReceipt memory receipt ) = ILayerZero(params.oftAddress).quoteOFT(sendParams);
        sendParams.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = ILayerZero(params.oftAddress).quoteSend(sendParams, false);

        params.proxy.doCallWithValue{value: fee.nativeFee}(
            params.oftAddress,
            abi.encodeCall(ILayerZero.send, (sendParams, fee, address(params.proxy))),
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
