// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IFacetBase } from "./IFacetBase.sol";

interface IWSTETHFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(uint256 amount) external;

    function claimWithdrawal(uint256 requestId) external;

    function requestWithdraw(uint256 amountToRedeem) external returns (uint256[] memory requestIds);

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REQUEST_WITHDRAW() external pure returns (bytes32);

    function weth() external view returns (address);

    function withdrawQueue() external view returns (address);

    function wsteth() external view returns (address);

}
