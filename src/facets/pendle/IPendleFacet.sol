// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IPendleFacet
 * @notice PAU facet for redeeming Pendle PT+YT (PY) tokens back to the underlying yield token after
 *         market expiry.
 */
interface IPendleFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when PY tokens are redeemed for the underlying yield token.
     * @param  market              Address of the Pendle market.
     * @param  pyAmountIn          Amount of PY tokens redeemed.
     * @param  totalTokenOutAmount Total amount of underlying yield tokens received.
     */
    event PendleRedeem(address indexed market, uint256 pyAmountIn, uint256 totalTokenOutAmount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Redeems PY tokens for the underlying yield token via the Pendle router.
     * @notice Only works on expired markets.
     * @param  market       Address of the Pendle market.
     * @param  pyAmountIn   Amount of PY tokens to redeem.
     * @param  minAmountOut Minimum underlying yield tokens to receive.
     */
    function redeem(address market, uint256 pyAmountIn, uint256 minAmountOut) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for Pendle PT redeem operations, combined with the market address to
     *         form the per-market keys.
     */
    function LIMIT_REDEEM() external pure returns (bytes32);

    /// @notice Address of the Pendle router contract (immutable).
    function router() external view returns (address);

}
