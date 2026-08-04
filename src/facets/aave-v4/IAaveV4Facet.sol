// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IAaveV4Facet
 * @notice PAU facet for supplying and withdrawing assets via Aave V4 (Hub & Spoke) markets.
 * @dev    A market is identified by `(spoke, reserveId)`; there is no receipt/aToken. The
 *         underlying asset and supplied position are read from the spoke.
 */
interface IAaveV4Facet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an underlying asset is supplied to an Aave V4 market.
     * @param  spoke     Address of the spoke hosting the market.
     * @param  reserveId Reserve identifier on the spoke.
     * @param  amount    Amount of underlying asset deposited.
     */
    event AaveV4Deposit(address indexed spoke, uint256 indexed reserveId, uint256 amount);

    /**
     * @notice Emitted when the max slippage for an Aave V4 market is updated.
     * @param  spoke       Address of the spoke hosting the market.
     * @param  reserveId   Reserve identifier on the spoke.
     * @param  maxSlippage New max slippage in 1e18 precision (1e18 = no slippage).
     */
    event AaveV4MaxSlippageSet(
        address indexed spoke,
        uint256 indexed reserveId,
        uint256         maxSlippage
    );

    /**
     * @notice Emitted when underlying assets are withdrawn from an Aave V4 market.
     * @param  spoke           Address of the spoke hosting the market.
     * @param  reserveId       Reserve identifier on the spoke.
     * @param  amountWithdrawn Actual amount of underlying asset withdrawn.
     */
    event AaveV4Withdraw(
        address indexed spoke,
        uint256 indexed reserveId,
        uint256         amountWithdrawn
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Supplies underlying asset into the Aave V4 market `(spoke, reserveId)`.
     * @param  spoke     Address of the spoke hosting the market.
     * @param  reserveId Reserve identifier on the spoke (determines the underlying).
     * @param  amount    Amount of underlying asset to supply.
     */
    function deposit(address spoke, uint256 reserveId, uint256 amount) external;

    /**
     * @notice Sets the max slippage for deposit operations on a given `(spoke, reserveId)` market.
     * @dev    A tolerance of 1e18 or above demands a supplied position at least equal to the amount
     *         deposited, which the reserve's round-down share accounting never returns, so every
     *         deposit into the market would revert.
     * @param  spoke       Address of the spoke hosting the market.
     * @param  reserveId   Reserve identifier on the spoke.
     * @param  maxSlippage Max slippage in 1e18 precision (1e18 = no slippage).
     */
    function setMaxSlippage(address spoke, uint256 reserveId, uint256 maxSlippage) external;

    /**
     * @notice Withdraws underlying assets from the Aave V4 market `(spoke, reserveId)`.
     * @dev    Passing `type(uint256).max` withdraws the entire supplied position.
     * @param  spoke           Address of the spoke hosting the market.
     * @param  reserveId       Reserve identifier on the spoke (determines the underlying).
     * @param  amount          Amount of underlying asset to withdraw.
     * @return amountWithdrawn Actual amount of underlying withdrawn.
     */
    function withdraw(address spoke, uint256 reserveId, uint256 amount)
        external
        returns (uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived deposit rate limit key for a given `(spoke, reserveId)` market.
     * @param  spoke      Address of the spoke hosting the market.
     * @param  reserveId  Reserve identifier on the spoke.
     * @param  hub        Hub the reserve settles against.
     * @param  assetId    Identifier of the reserve's asset on the hub.
     * @param  underlying Underlying asset of the reserve.
     * @return key        Derived rate limit key.
     */
    function getDepositRateLimitKey(
        address spoke,
        uint256 reserveId,
        address hub,
        uint16  assetId,
        address underlying
    )
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the configured max slippage for a given `(spoke, reserveId)` market.
     * @param  spoke       Address of the spoke hosting the market.
     * @param  reserveId   Reserve identifier on the spoke.
     * @return maxSlippage Max slippage in 1e18 precision. Zero means not set.
     */
    function getMaxSlippage(address spoke, uint256 reserveId)
        external
        view
        returns (uint256 maxSlippage);

    /**
     * @notice Returns the derived withdraw rate limit key for a given `(spoke, reserveId)` market.
     * @param  spoke     Address of the spoke hosting the market.
     * @param  reserveId Reserve identifier on the spoke.
     * @return key       Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address spoke, uint256 reserveId)
        external
        pure
        returns (bytes32 key);

}
