// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControl
} from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

/**
 * @title  IALMProxyFreezable
 * @notice Proxy contract with freezer and allocator roles. Allocators execute calls through the
 *         proxy, and freezers can revoke allocator access as an emergency measure.
 */
interface IALMProxyFreezable is IAccessControl {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a freezer removes an allocator from the system.
     * @param  allocator Address of the allocator that was removed.
     */
    event AllocatorRemoved(address indexed allocator);

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
     * @notice This function allows a freezer to remove an allocator.
     * @param  allocator The address of the allocator to be removed.
     */
    function removeAllocator(address allocator) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Role identifier for freezer accounts that can remove allocators.
    function FREEZER_ROLE() external view returns (bytes32);

    /// @notice Role identifier for allocator accounts authorized to execute proxy calls.
    function ALLOCATOR_ROLE() external view returns (bytes32);

}
