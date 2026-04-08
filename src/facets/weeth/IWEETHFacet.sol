// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IWEETHFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event WEETHClaimWithdrawal(
        address indexed weethModule,
        uint256 indexed requestId,
        uint256         ethReceived
    );

    event WEETHDeposit(uint256 amount, uint256 eethAmount, uint256 shares);

    event WEETHRequestWithdraw(
        address indexed weethModule,
        uint256 indexed requestId,
        uint256         eethAmount,
        uint256         weethShares
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function claimWithdrawal(address weethModule, uint256 requestId)
        external
        returns (uint256 ethReceived);

    function deposit(uint256 amount, uint256 minSharesOut) external returns (uint256 shares);

    function requestWithdraw(address weethModule, uint256 weethShares, uint256 minEETHShares)
        external
        returns (uint256 requestId);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_REQUEST_WITHDRAW() external pure returns (bytes32);

    function weth() external view returns (address);

    function weeth() external view returns (address);

}
