// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ILayerZeroFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function transfer(address oftAddress, uint256 amount, uint32 destinationEndpointId)
        external
        payable;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_TRANSFER() external pure returns (bytes32);

    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32);
}
