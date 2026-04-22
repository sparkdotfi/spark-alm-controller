// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ISuperstateFacet
 * @notice PAU facet for subscribing to Superstate USTB using USDC. Only compatible with USTB and
 *         USDC.
 */
interface ISuperstateFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when USDC is subscribed to Superstate USTB.
     * @param  usdcAmount Amount of USDC subscribed (6-decimal precision).
     */
    event SuperstateSubscribe(uint256 usdcAmount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Subscribes USDC to Superstate USTB.
     * @param  usdcAmount Amount of USDC to subscribe (6-decimal precision).
     */
    function subscribe(uint256 usdcAmount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Rate limit key for Superstate subscribe operations.
    function LIMIT_SUBSCRIBE() external pure returns (bytes32);

    /// @notice Address of the USDC token contract (immutable).
    function usdc() external view returns (address);

    /// @notice Address of the Superstate USTB token contract (immutable).
    function ustb() external view returns (address);

}
