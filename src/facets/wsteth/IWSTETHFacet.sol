// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IWSTETHFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event WSTETHClaimWithdrawal(uint256 indexed requestId, uint256 wethClaimed);

    event WSTETHDeposit(uint256 amount);

    event WSTETHRequestWithdraw(uint256 amountToRedeem, uint256 stethAmount, uint256[] requestIds);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external;

    function deposit(uint256 amount) external;

    function requestWithdraw(uint256 amountToRedeem) external returns (uint256[] memory requestIds);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REQUEST_WITHDRAW() external pure returns (bytes32);

    function weth() external view returns (address);

    function withdrawQueue() external view returns (address);

    function wsteth() external view returns (address);

}
