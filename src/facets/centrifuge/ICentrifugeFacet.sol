// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ICentrifugeFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CentrifugeRecipientSet(uint16 indexed centrifugeId, bytes32 indexed recipient);

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function setRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function cancelDepositRequest(address token) external;

    function claimCancelDepositRequest(address token) external;

    function cancelRedeemRequest(address token) external;

    function claimCancelRedeemRequest(address token) external;

    function transferShares(address token, uint128 amount, uint16 centrifugeId) external payable;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_TRANSFER() external pure returns (bytes32);

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REDEEM() external pure returns (bytes32);

    function REQUEST_ID() external pure returns (uint256);

    function getRecipient(uint16 centrifugeId) external view returns (bytes32);

}
