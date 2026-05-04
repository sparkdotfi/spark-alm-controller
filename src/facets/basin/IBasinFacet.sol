// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IBasinFacet
 * @notice PAU facet for depositing into and withdrawing from Basin liquidity pools.
 */
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
     * @param  basin        The address of the basin.
     * @param  asset        The address of the asset deposited.
     * @param  amount       The amount of the asset deposited.
     * @param  minSharesOut The minimum number of shares willing to receive.
     * @return shares       The number of shares received.
     */
    function deposit(address basin, address asset, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 shares);

    /**
     * @notice Withdraw up to `maxAmount` of `asset` from `basin`, return `assetsWithdrawn`.
     * @param  basin             The address of the basin.
     * @param  asset             The address of the asset withdrawn.
     * @param  maxAmount         The maximum amount of the asset to withdraw.
     * @param  minConversionRate The minimum conversion rate willing to accept.
     * @return assetsWithdrawn   The amount of the asset withdrawn.
     */
    function withdraw(address basin, address asset, uint256 maxAmount, uint256 minConversionRate)
        external
        returns (uint256 assetsWithdrawn);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived deposit rate limit key for a basin and asset.
     * @param  basin Address of the basin contract.
     * @param  asset Address of the asset.
     * @return key   Derived rate limit key.
     */
    function getDepositRateLimitKey(address basin, address asset)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the derived withdraw rate limit key for a basin and asset.
     * @param  basin Address of the basin contract.
     * @param  asset Address of the asset.
     * @return key   Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address basin, address asset)
        external
        pure
        returns (bytes32 key);

}
