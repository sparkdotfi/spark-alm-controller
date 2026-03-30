// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IDAIUSDSFacet is IFacetBase {

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external;

    function swapDAIToUSDS(uint256 daiAmount) external;

}
