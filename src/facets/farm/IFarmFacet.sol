// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IFarmFacet
 * @notice PAU facet for staking tokens into and withdrawing from staking reward farms. Withdrawal
 *         also claims pending rewards.
 */
interface IFarmFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when staking tokens are deposited into a farm.
     * @param  farm   Address of the farm contract.
     * @param  amount Amount of staking tokens deposited.
     */
    event FarmDeposit(address indexed farm, uint256 amount);

    /**
     * @notice Emitted when rewards are claimed from a farm without unstaking.
     * @param  farm Address of the farm contract.
     */
    event FarmReward(address indexed farm, uint256 amount);

    /**
     * @notice Emitted when staking tokens are withdrawn from a farm.
     * @param  farm   Address of the farm contract.
     * @param  amount Amount of staking tokens withdrawn.
     */
    event FarmWithdraw(address indexed farm, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Claims pending rewards from a farm without unstaking.
     * @param  farm   Address of the farm contract.
     * @return reward Amount of rewards claimed.
     */
    function claimReward(address farm) external returns (uint256 reward);

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
     * @return reward Amount of rewards claimed.
     */
    function withdraw(address farm, uint256 amount) external returns (uint256 reward);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived deposit rate limit key for a farm and staking token.
     * @param  farm         Address of the farm contract.
     * @param  stakingToken Address of the staking token for the farm.
     * @return key          Derived rate limit key.
     */
    function getDepositRateLimitKey(address farm, address stakingToken)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the derived withdraw rate limit key for a farm.
     * @param  farm Address of the farm contract.
     * @return key  Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address farm) external pure returns (bytes32 key);

}
