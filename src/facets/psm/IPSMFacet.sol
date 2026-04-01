// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IPSMFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function swapUSDCToUSDS(uint256 usdcAmount) external;

    function swapUSDSToUSDC(uint256 usdcAmount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_USDS_TO_USDC() external pure returns (bytes32);

    function dai() external view returns (address);

    function daiUSDS() external view returns (address);

    function psm() external view returns (address);

    function usdc() external view returns (address);

    function usds() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function to18ConversionFactor() external view returns (uint256);

}
