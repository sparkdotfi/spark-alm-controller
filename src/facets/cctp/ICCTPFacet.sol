// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ICCTPFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CCTPMaxFeeCapSet(uint256 maxFeeCap);

    event CCTPMintRecipientSet(uint32 indexed destinationDomain, bytes32 indexed mintRecipient);

    // NOTE: Used to track individual transfers for off-chain processing of CCTP transactions.
    event CCTPTransferInitiated(
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256         amount
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function setMaxFeeCap(uint256 maxFeeCap) external;

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient) external;

    function transfer(uint256 amount, uint32 destinationDomain) external;

    function transferWithFee(uint256 amount, uint256 maxFee, uint32 destinationDomain) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function DESTINATION_CALLER() external pure returns (bytes32);

    function LIMIT_TO_CCTP() external pure returns (bytes32);

    function LIMIT_TO_DOMAIN() external pure returns (bytes32);

    function MAX_FEE() external pure returns (uint256);

    function MAX_FINALITY_THRESHOLD() external pure returns (uint32);

    function cctp() external view returns (address);

    function maxFeeCap() external view returns (uint256);

    function usdc() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getMintRecipient(uint32 destinationDomain) external view returns (bytes32);

}
