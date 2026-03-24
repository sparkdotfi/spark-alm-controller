// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IFacetBase } from "./IFacetBase.sol";

interface ISuperstateFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function subscribe(uint256 usdcAmount) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_SUBSCRIBE() external pure returns (bytes32);

    function usdc() external view returns (address);

    function ustb() external view returns (address);

}
