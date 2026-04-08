// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IUSDSFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event USDSBurn(uint256 usdsAmount);

    event USDSMint(uint256 usdsAmount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function burn(uint256 usdsAmount) external;

    function mint(uint256 usdsAmount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_MINT() external pure returns (bytes32);

    function usds() external view returns (address);

    function vault() external view returns (address);

}
