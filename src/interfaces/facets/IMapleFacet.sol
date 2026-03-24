// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IFacetBase } from "./IFacetBase.sol";

interface IMapleFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function cancelRedemption(address mapleToken, uint256 shares) external;

    function requestRedemption(address mapleToken, uint256 shares) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_REDEEM() external pure returns (bytes32);

}
