// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IERC7540Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event ERC7540ClaimDeposit(address indexed token, uint256 shares);

    event ERC7540ClaimRedeem(address indexed token, uint256 assets);

    event ERC7540RequestDeposit(address indexed token, uint256 assets);

    event ERC7540RequestRedeem(address indexed token, uint256 shares);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function claimDeposit(address token) external;

    function claimRedeem(address token) external;

    function requestDeposit(address token, uint256 amount) external;

    function requestRedeem(address token, uint256 shares) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REDEEM() external pure returns (bytes32);

}
