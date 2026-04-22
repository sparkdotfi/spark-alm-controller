// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ILayerZeroFacet
 * @notice PAU facet for cross-chain token transfers via LayerZero V2 OFT (Omnichain Fungible Token)
 *         contracts. Requires ETH for cross-chain messaging fees (payable).
 */
interface ILayerZeroFacet is IFacet {

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
     * @param  oftAddress            Address of the OFT contract on the source chain.
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     * @param  amount                Amount of tokens transferred (local decimals).
     * @param  nativeFeePaid         Amount of native gas token paid for messaging.
     */
    event LayerZeroTransfer(
        address indexed oftAddress,
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
     * @param  oftAddress            Address of the OFT contract.
     * @param  amount                Amount of tokens to transfer (local decimals).
     * @param  destinationEndpointId LayerZero endpoint ID for the destination chain.
     */
    function transfer(address oftAddress, uint256 amount, uint32 destinationEndpointId)
        external
        payable;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for LayerZero transfers, combined with the OFT address and destination
     *         endpoint ID to form the per-route keys.
     */
    function LIMIT_TRANSFER() external pure returns (bytes32);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the configured recipient for a LayerZero endpoint.
     * @param  destinationEndpointId LayerZero endpoint ID.
     * @return recipient             Bytes32-encoded recipient. Zero if not set.
     */
    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32 recipient);

}
