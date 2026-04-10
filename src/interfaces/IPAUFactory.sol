// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IPAUFactory
 * @notice Factory for deploying complete PAU systems. Each deployment creates an
 *         AccessControls, ALMProxy, RateLimits, and Controller wired together under one admin.
 */
interface IPAUFactory {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a new PAU system is deployed.
     * @param  admin          Address of the admin that controls the deployed system.
     * @param  controller     Address of the deployed Controller contract.
     * @param  accessControls Address of the deployed AccessControls contract.
     * @param  almProxy       Address of the deployed ALMProxy contract.
     * @param  rateLimits     Address of the deployed RateLimits contract.
     */
    event PAUDeployed(
        address indexed admin,
        address indexed controller,
        address         accessControls,
        address         almProxy,
        address         rateLimits
    );

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the beacon is the zero address.
    error ZeroBeacon();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Deploys a complete PAU system with all required components and role assignments.
     * @param  admin      Address that will be granted admin over the deployed system.
     * @return controller Address of the deployed Controller contract.
     */
    function deploy(address admin) external returns (address controller);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Address of the Beacon that deployed Controllers will sync integrations from
     *         (immutable).
     */
    function beacon() external view returns (address);

}
