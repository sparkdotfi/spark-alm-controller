// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IEnumerableIntegrations } from "./IEnumerableIntegrations.sol";

/**
 * @title  IController
 * @notice Controller that manages integration lifecycle and routes incoming calls to facets via
 *         a dispatch table synced from the Beacon.
 */
interface IController is IEnumerableIntegrations {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when a call selector is not wired to a facet.
    error CallSelectorNotWired(bytes4 callSelector);

    /// @notice Thrown when an argument array is empty.
    error EmptyArray();

    /// @notice Thrown when the call data length is less than 4.
    error InvalidCallDataLength(uint256 callDataLength);

    /// @notice Thrown when the caller is not an admin.
    error NotAdmin(address caller);

    /// @notice Thrown when the access controls is the zero address.
    error ZeroAccessControls();

    /// @notice Thrown when the beacon is the zero address.
    error ZeroBeacon();

    /// @notice Thrown when the proxy is the zero address.
    error ZeroProxy();

    /// @notice Thrown when the rate limits is the zero address.
    error ZeroRateLimits();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Syncs integration configs from the Beacon and rebuilds the local dispatch table.
     * @param  ids Array of integration identifiers to update.
     */
    function updateIntegrations(bytes32[] calldata ids) external;

    /**
     * @notice Removes integrations and their selector dispatches from the controller.
     * @param  ids Array of integration identifiers to remove.
     */
    function removeIntegrations(bytes32[] calldata ids) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Address of the AccessControls contract.
    function accessControls() external view returns (address);

    /// @notice Address of the Beacon contract.
    function beacon() external view returns (address);

    /// @notice Address of the ALMProxy contract.
    function proxy() external view returns (address);

    /// @notice Address of the RateLimits contract.
    function rateLimits() external view returns (address);

}
