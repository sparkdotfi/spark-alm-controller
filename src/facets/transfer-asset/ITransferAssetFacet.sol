// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ITransferAssetFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event TransferAssetFacetTransfer(
        address indexed asset,
        address indexed destination,
        uint256         amount
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function transfer(address asset, address destination, uint256 amount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_TRANSFER() external pure returns (bytes32);

}
