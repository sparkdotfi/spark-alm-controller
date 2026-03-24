// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IFacetBase } from "./IFacetBase.sol";

interface IERC7540Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function claimRedeem(address token) external;

    function claimDeposit(address token) external;

    function requestDeposit(address token, uint256 amount) external;

    function requestRedeem(address token, uint256 shares) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REDEEM() external pure returns (bytes32);

}
