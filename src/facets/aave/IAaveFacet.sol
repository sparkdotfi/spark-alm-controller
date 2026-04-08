// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IAaveFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event AaveDeposit(address indexed aToken, uint256 amount);

    event AaveMaxSlippageSet(address indexed aToken, uint256 maxSlippage);

    event AaveWithdraw(address indexed aToken, uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(address aToken, uint256 amount) external;

    function setMaxSlippage(address aToken, uint256 maxSlippage) external;

    function withdraw(address aToken, uint256 amount) external returns (uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_WITHDRAW() external pure returns (bytes32);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getMaxSlippage(address aToken) external view returns (uint256);

}
