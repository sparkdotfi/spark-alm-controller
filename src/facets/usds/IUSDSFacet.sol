// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IUSDSFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function burn(uint256 usdsAmount) external;

    function mint(uint256 usdsAmount) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_MINT() external pure returns (bytes32);

}
