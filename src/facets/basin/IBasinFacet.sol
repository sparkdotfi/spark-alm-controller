// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

interface IBasinFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Event emitted when a deposit is made to a basin.
     * @param  basin  The address of the basin.
     * @param  asset  The address of the asset deposited.
     * @param  amount The amount of the asset deposited.
     * @param  shares The number of shares received.
     */
    event BasinDeposit(
        address indexed basin,
        address indexed asset,
        uint256         amount,
        uint256         shares
    );

    /**
     * @notice Event emitted when a withdrawal is made from a basin.
     * @param  basin           The address of the basin.
     * @param  asset           The address of the asset withdrawn.
     * @param  assetsWithdrawn The amount of the asset withdrawn.
     * @param  sharesBurned    The amount of shares burned.
     */
    event BasinWithdraw(
        address indexed basin,
        address indexed asset,
        uint256         assetsWithdrawn,
        uint256         sharesBurned
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Deposit `amount` of `asset` into `basin`, return `shares` received.
     * @param  basin  The address of the basin.
     * @param  asset  The address of the asset deposited.
     * @param  amount The amount of the asset deposited.
     * @return shares The number of shares received.
     */
    function deposit(address basin, address asset, uint256 amount)
        external
        returns (uint256 shares);

    /**
     * @notice Withdraw up to `maxAmount` of `asset` from `basin`, return `assetsWithdrawn`.
     * @param  basin           The address of the basin.
     * @param  asset           The address of the asset withdrawn.
     * @param  maxAmount       The maximum amount of the asset to withdraw.
     * @return assetsWithdrawn The amount of the asset withdrawn.
     */
    function withdraw(address basin, address asset, uint256 maxAmount)
        external
        returns (uint256 assetsWithdrawn);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Limit for deposit operations.
    function LIMIT_DEPOSIT() external pure returns (bytes32);

    /// @notice Limit for withdraw operations.
    function LIMIT_WITHDRAW() external pure returns (bytes32);

}
