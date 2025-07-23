// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

struct MessagingFee {
    uint256 nativeFee; // gas amount in native gas token
    uint256 lzTokenFee; // gas amount in ZRO token
}

struct MessagingReceipt {
    bytes32      guid;
    uint64       nonce;
    MessagingFee fee;
}

/**
 * @dev Struct representing OFT fee details.
 * @dev Future proof mechanism to provide a standardized way to communicate fees to things like a UI.
 */
struct OFTFeeDetail {
    int256 feeAmountLD; // Amount of the fee in local decimals.
    string description; // Description of the fee.
}

/**
 * @dev Struct representing OFT limit information.
 * @dev These amounts can change dynamically and are up the the specific oft implementation.
 */
struct OFTLimit {
    uint256 minAmountLD; // Minimum amount in local decimals that can be sent to the recipient.
    uint256 maxAmountLD; // Maximum amount in local decimals that can be sent to the recipient.
}

struct OFTReceipt {
    uint256 amountSentLD; // Amount of tokens ACTUALLY debited from the sender in local decimals.
    // @dev In non-default implementations, the amountReceivedLD COULD differ from this value.
    uint256 amountReceivedLD; // Amount of tokens to be received on the remote side.
}

/**
 * @dev Struct representing token parameters for the OFT send() operation.
 */
 struct SendParam {
     uint32  dstEid; // Destination endpoint ID.
     bytes32 to; // Recipient address.
     uint256 amountLD; // Amount to send in local decimals.
     uint256 minAmountLD; // Minimum amount to send in local decimals.
     bytes   extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
     bytes   composeMsg; // The composed message for the send() operation.
     bytes   oftCmd; // The OFT command to be executed, unused in default OFT implementations.
 }

interface ILayerZero {

    function quoteOFT(
        SendParam calldata _sendParam
    ) external view returns (OFTLimit memory, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory);

    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory msgFee);

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);

    function token() external view returns (address);

    function approvalRequired() external pure returns (bool);

}
