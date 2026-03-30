// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ITransferAssetFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function transfer(address asset, address destination, uint256 amount) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_TRANSFER() external pure returns (bytes32);

}
