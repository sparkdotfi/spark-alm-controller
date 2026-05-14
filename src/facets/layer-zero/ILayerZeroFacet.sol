// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ILayerZeroFacet
 * @notice PAU facet for cross-chain token transfers via LayerZero V2 OFT (Omnichain Fungible Token)
 *         contracts. Requires ETH for cross-chain messaging fees (payable).
 */
interface ILayerZeroFacet is IFacet {

    /**
     * @notice Struct representing messaging fee details.
     * @param  nativeFee  Gas amount in native gas token.
     * @param  lzTokenFee Gas amount in ZRO token.
     */
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    /**
     * @notice Struct representing token parameters for the OFT send() operation.
     * @param  dstEid       Destination endpoint ID.
     * @param  to           Recipient address.
     * @param  amountLD     Amount to send in local decimals.
     * @param  minAmountLD  Minimum amount to send in local decimals.
     * @param  extraOptions Additional options supplied by the caller to be used in the LayerZero
     *                      message.
     * @param  composeMsg   Composed message for the send() operation.
     * @param  oftCmd       OFT command to be executed, unused in default OFT implementations.
     */
    struct SendParam {
        uint32  dstEid;
        bytes32 to;
        uint256 amountLD;
        uint256 minAmountLD;
        bytes   extraOptions;
        bytes   composeMsg;
        bytes   oftCmd;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a recipient is configured for a LayerZero endpoint.
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @param  layerZeroRecipient    Bytes32-encoded recipient address.
     */
    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);

    /**
     * @notice Emitted when a cross-chain token transfer is initiated.
     * @param  oft                   Address of the OFT contract on the source chain.
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @param  amount                Amount of tokens transferred (local decimals).
     * @param  nativeFeePaid         Amount of native gas token paid for messaging.
     */
    event LayerZeroTransfer(
        address indexed oft,
        uint32  indexed destinationEndpointId,
        uint256         amount,
        uint256         nativeFeePaid
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Sets the recipient for a LayerZero destination endpoint.
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @param  recipient             Bytes32-encoded recipient address.
     */
    function setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    /**
     * @notice Transfers tokens cross-chain via a LayerZero OFT contract.
     * @notice Excess native fee is refunded to the caller.
     * @param  oft                   Address of the OFT contract.
     * @param  amount                Amount of tokens to transfer (local decimals).
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     */
    function transfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        payable;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the configured recipient for a LayerZero endpoint.
     * @param  destinationEndpointId LayerZero endpoint ID.
     * @return recipient             Bytes32-encoded recipient. Zero if not set.
     */
    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32 recipient);

    /**
     * @notice Returns the derived transfer rate limit key for an OFT, token, and destination.
     * @param  oft                   Address of the OFT contract.
     * @param  peer                  Bytes32-encoded peer address on the destination chain.
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @param  token                 Address of token transferred by OFT.
     * @return key                   Derived rate limit key.
     */
    function getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    )
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the send parameters and messaging fee for a cross-chain token transfer.
     *         This function is to be used by allocators to estimate the messaging fee (msg.value)
     *         required for a transfer.
     * @param  oft                   Address of the OFT contract.
     * @param  amount                Amount of tokens to transfer (local decimals).
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @return sendParams            Send parameters for the send operation.
     * @return fee                   Messaging fee for the send operation.
     */
    function quoteTransfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        returns (
            SendParam    memory sendParams,
            MessagingFee memory fee
        );

}
