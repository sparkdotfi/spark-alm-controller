// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IAaveFacet
 * @notice PAU facet for supplying and withdrawing assets via Aave V3 lending pools.
 */
interface IAaveFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an underlying asset is supplied to an Aave pool.
     * @param  aToken Address of the aToken representing the Aave market.
     * @param  amount Amount of underlying asset deposited.
     */
    event AaveDeposit(address indexed aToken, uint256 amount);

    /**
     * @notice Emitted when the max slippage for an aToken market is updated.
     * @param  aToken      Address of the aToken.
     * @param  maxSlippage New max slippage in 1e18 precision (1e18 = no slippage).
     */
    event AaveMaxSlippageSet(address indexed aToken, uint256 maxSlippage);

    /**
     * @notice Emitted when underlying assets are withdrawn from an Aave pool.
     * @param  aToken          Address of the aToken representing the Aave market.
     * @param  amountWithdrawn Actual amount of underlying asset withdrawn.
     */
    event AaveWithdraw(address indexed aToken, uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Supplies underlying asset into the Aave pool for `aToken`.
     * @param  aToken Address of the aToken (determines pool and underlying).
     * @param  amount Amount of underlying asset to supply.
     */
    function deposit(address aToken, uint256 amount) external;

    /**
     * @notice Sets the max slippage for deposit operations on a given aToken.
     * @param  aToken      Address of the aToken.
     * @param  maxSlippage Max slippage in 1e18 precision (1e18 = no slippage).
     */
    function setMaxSlippage(address aToken, uint256 maxSlippage) external;

    /**
     * @notice Withdraws underlying assets from the Aave pool by redeeming aTokens.
     * @param  aToken          Address of the aToken (determines pool and underlying).
     * @param  amount          Amount of underlying asset to withdraw.
     * @return amountWithdrawn Actual amount of underlying withdrawn.
     */
    function withdraw(address aToken, uint256 amount) external returns (uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived deposit rate limit key for a given Aave aToken, pool, and
     *         underlying asset.
     * @param  aToken          Address of the aToken.
     * @param  pool            Address of the pool.
     * @param  underlyingAsset Address of the underlying asset.
     * @return key             Derived rate limit key.
     */
    function getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the configured max slippage for a given aToken market.
     * @param  aToken      Address of the aToken.
     * @return maxSlippage Max slippage in 1e18 precision. Zero means not set.
     */
    function getMaxSlippage(address aToken) external view returns (uint256 maxSlippage);

    /**
     * @notice Returns the derived withdraw rate limit key for a given Aave aToken and pool.
     * @param  aToken Address of the aToken.
     * @param  pool   Address of the pool.
     * @return key    Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address aToken, address pool)
        external
        pure
        returns (bytes32 key);

}
