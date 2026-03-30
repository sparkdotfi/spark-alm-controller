// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IPSM3Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(address asset, uint256 amount) external returns (uint256 shares);

    function withdraw(address asset, uint256 maxAmount) external returns (uint256 assetsWithdrawn);

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_WITHDRAW() external pure returns (bytes32);

}
