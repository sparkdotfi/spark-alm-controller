// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IParameterKeysErrors }    from "./IParameterKeysErrors.sol";
import { IParameterHelpersErrors } from "./IParameterHelpersErrors.sol";

/**
 * @title  Interface for a Parameters contract.
 * @notice A Parameters contract allows admins to set parameters, including whether an account is an
 *         admin, and allows any account/contract to query the values of parameters.
 */
interface IParameters is IParameterKeysErrors, IParameterHelpersErrors, IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a parameter is set.
     * @param  keyHash The hash of the key of the parameter.
     * @param  key     The key of the parameter (which is generally a human-readable string).
     * @param  value   The value of the parameter (which can represent any value type).
     * @dev    Values that are not value types (e.g. bytes, arrays, structs, etc.) must be the hash
     *         of their contents.
     * @dev    When passing the key as the first argument when emitting this event, it is
     *         automatically hashed since reference types are not indexable, and the hash is thus
     *         the indexable value.
     */
    event ParameterSet(string indexed keyHash, string key, bytes32 value);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when no keys are provided (e.g. when setting or getting parameters).
    error NoKeys();

    /// @notice Thrown when the array length mismatch (e.g. when setting multiple parameters).
    error ArrayLengthMismatch();

    /// @notice Thrown when an admin is the zero address.
    error ZeroAdmin();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Sets several parameters.
     * @param  keys   The keys of each parameter to set.
     * @param  values The values of each parameter.
     * @dev    The length of the `keys` and `values` arrays must be the same.
     * @dev    The caller must be an admin.
     */
    function set(string[] calldata keys, bytes32[] calldata values) external;

    /**
     * @notice Sets a parameter.
     * @param  key   The key of the parameter to set.
     * @param  value The value of the parameter.
     * @dev    The caller must be an admin.
     */
    function set(string calldata key, bytes32 value) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @return The role for the controller, which can set parameters.
     */
    function CONTROLLER_ROLE() external view returns (bytes32);

    /**
     * @notice Gets the values of several parameters.
     * @param  keys   The keys of each parameter to get.
     * @return values The values of each parameter.
     * @dev    The default value for each parameter is bytes32(0).
     */
    function get(string[] calldata keys) external view returns (bytes32[] memory values);

    /**
     * @notice Gets the value of a parameter.
     * @param  key   The key of the parameter to get.
     * @return value The value of the parameter.
     * @dev    The default value for a parameter is bytes32(0).
     */
    function get(string calldata key) external view returns (bytes32 value);

    /**
     * @notice Checks if the contract supports an interface.
     * @param  interfaceId The interface identifier to check.
     * @return bool        True if the contract supports the interface, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
