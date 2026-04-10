// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

/**
 * @title  IDAIUSDSFacet
 * @notice PAU facet for 1:1 swaps between DAI and USDS using the SKY DAI-USDS migrator contract.
 */
interface IDAIUSDSFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when DAI is converted to USDS.
     * @param  daiAmount Amount of DAI swapped (18-decimal precision).
     */
    event DAIUSDSSwapDAIToUSDS(uint256 daiAmount);

    /**
     * @notice Emitted when USDS is converted to DAI.
     * @param  usdsAmount Amount of USDS swapped (18-decimal precision).
     */
    event DAIUSDSSwapUSDSToDAI(uint256 usdsAmount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Converts DAI to USDS 1:1 via the DAI-USDS migrator.
     * @param  daiAmount Amount of DAI to swap (18-decimal precision).
     */
    function swapDAIToUSDS(uint256 daiAmount) external;

    /**
     * @notice Converts USDS to DAI 1:1 via the DAI-USDS migrator.
     * @param  usdsAmount Amount of USDS to swap (18-decimal precision).
     */
    function swapUSDSToDAI(uint256 usdsAmount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Address of the DAI token contract (immutable).
    function dai() external view returns (address);

    /// @notice Address of the DAI-USDS migrator contract (immutable).
    function daiUSDS() external view returns (address);

    /// @notice Address of the USDS token contract (immutable).
    function usds() external view returns (address);

}
