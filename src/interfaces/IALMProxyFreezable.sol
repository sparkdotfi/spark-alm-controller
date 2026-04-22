// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControl
} from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

/**
 * @title  IALMProxyFreezable
 * @notice Proxy contract with freezer and relayer roles. Relayers execute calls through the proxy,
 *         and freezers can revoke relayer access as an emergency measure.
 */
interface IALMProxyFreezable is IAccessControl {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a freezer removes a relayer from the system.
     * @param  relayer Address of the relayer that was removed.
     */
    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the admin is the zero address.
    error ZeroAdmin();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Performs a standard call to the specified `target` with the given `data`.
     *         Reverts if the call fails.
     * @param  target The address of the target contract to call.
     * @param  data   The calldata that will be sent to the target contract.
     * @return result The returned data from the call.
     */
    function doCall(address target, bytes calldata data) external returns (bytes memory result);

    /**
     * @notice This function allows for transferring `value` (ether) along with the call to the
     *         target contract. Reverts if the call fails.
     * @param  target The address of the target contract to call.
     * @param  data   The calldata that will be sent to the target contract.
     * @param  value  The amount of Ether (in wei) to send with the call.
     * @return result The returned data from the call.
     */
    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        returns (bytes memory result);

    /**
     * @notice This function allows a freezer to remove a relayer.
     * @param  relayer The address of the relayer to be removed.
     */
    function removeRelayer(address relayer) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Role identifier for freezer accounts that can remove relayers.
    function FREEZER() external view returns (bytes32);

    /// @notice Role identifier for relayer accounts authorized to execute proxy calls.
    function RELAYER() external view returns (bytes32);

}
