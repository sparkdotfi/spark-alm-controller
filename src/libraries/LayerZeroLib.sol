// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    ILayerZero,
    SendParam,
    OFTReceipt,
    MessagingFee,
    OFTLimit,
    OFTFeeDetail
} from "../interfaces/ILayerZero.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IERC20Like }  from "../interfaces/Common.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

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
    ) external {
        require(layerZeroRecipient != bytes32(0), "LayerZeroLib/recipient-not-set");

        address token = ILayerZero(oftAddress).token();

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZero(oftAddress).approvalRequired()) {
            ApproveLib.approve(token, address(proxy), oftAddress, amount);
        }

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : layerZeroRecipient,
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        sendParams.minAmountLD = _getQuotedAmountReceivedLD(proxy, oftAddress, sendParams);

        MessagingFee memory fee = ILayerZero(oftAddress).quoteSend(sendParams, false);

        uint256 balanceBefore = IERC20Like(token).balanceOf(address(proxy));

        proxy.doCallWithValue{value: fee.nativeFee}(
            oftAddress,
            abi.encodeCall(ILayerZero.send, (sendParams, fee, address(proxy))),
            fee.nativeFee
        );

        uint256 balanceAfter = IERC20Like(token).balanceOf(address(proxy));

        _rateLimited(
            rateLimits,
            keccak256(
                abi.encode(
                    LIMIT_LAYERZERO_TRANSFER,
                    oftAddress,
                    destinationEndpointId
                )
            ),
            balanceAfter >= balanceBefore ? 0 : balanceBefore - balanceAfter
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _getQuotedAmountReceivedLD(
        IALMProxy        proxy,
        address          oftAddress,
        SendParam memory sendParams
    )
        internal returns (uint256)
    {
        // Query the min amount received on the destination chain and set it.
        ( , , OFTReceipt memory receipt ) = abi.decode(
            proxy.doCall(
                oftAddress,
                abi.encodeCall(ILayerZero.quoteOFT, (sendParams))
            ),
            (OFTLimit, OFTFeeDetail[], OFTReceipt)
        );

        return receipt.amountReceivedLD;
    }

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
