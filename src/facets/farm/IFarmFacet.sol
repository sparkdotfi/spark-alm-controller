// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

/**
 * @title  IFarmFacet
 * @notice PAU facet for staking tokens into and withdrawing from staking reward farms. Withdrawal
 *         also claims pending rewards.
 */
interface IFarmFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when staking tokens are deposited into a farm.
     * @param  farmToken Address of the farm's staking token.
     * @param  amount    Amount of staking tokens deposited.
     */
    event FarmDeposit(address indexed farmToken, uint256 amount);

    /**
     * @notice Emitted when staking tokens are withdrawn from a farm.
     * @param  farmToken Address of the farm's staking token.
     * @param  amount    Amount of staking tokens withdrawn.
     */
    event FarmWithdraw(address indexed farmToken, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Stakes tokens into a farm contract.
     * @param  farm   Address of the farm contract.
     * @param  amount Amount of staking tokens to deposit.
     */
    function deposit(address farm, uint256 amount) external;

    /**
     * @notice Unstakes tokens from a farm and claims pending rewards.
     * @param  farm   Address of the farm contract.
     * @param  amount Amount of staking tokens to withdraw.
     */
    function withdraw(address farm, uint256 amount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for farm deposit operations, combined with the farm address to form
     *         the per-farm keys.
     */
    function LIMIT_DEPOSIT() external pure returns (bytes32);

    /**
     * @notice Rate limit key for farm withdraw operations, combined with the farm address to form
     *         the per-farm keys.
     */
    function LIMIT_WITHDRAW() external pure returns (bytes32);

}
