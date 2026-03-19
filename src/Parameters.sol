// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IParameters } from "./interfaces/IParameters.sol";

/**
 * @notice A Parameters contract stores key-value pairs of parameters used by a protocol. Keys
 *         should be globally unique and human-readable strings, for easier parsing and indexing.
 *         Keys can only be set by account with `CONTROLLER_ROLE`.
 */
contract Parameters is IParameters, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IParameters
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER");

    mapping(string key => bytes32 value) internal _parameters;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    /**
     * @notice Constructor for the implementation contract.
     */
    constructor(address admin) {
        require(admin != address(0), ZeroAdmin());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /// @inheritdoc IParameters
    function set(string[] calldata keys, bytes32[] calldata values)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        require(keys.length > 0,              NoKeys());
        require(keys.length == values.length, ArrayLengthMismatch());

        for (uint256 i; i < keys.length; ++i) {
            _setParameter(keys[i], values[i]);
        }
    }

    /// @inheritdoc IParameters
    function set(string calldata key, bytes32 value) external onlyRole(CONTROLLER_ROLE) {
        _setParameter(key, value);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /// @inheritdoc IParameters
    function get(string[] calldata keys) external view returns (bytes32[] memory values) {
        require(keys.length > 0, NoKeys());

        values = new bytes32[](keys.length);

        for (uint256 i; i < keys.length; ++i) {
            values[i] = _parameters[keys[i]];
        }
    }

    /// @inheritdoc IParameters
    function get(string calldata key) external view returns (bytes32 value) {
        return _parameters[key];
    }

    /// @inheritdoc IParameters
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IParameters, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IParameters).interfaceId || super.supportsInterface(interfaceId);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _setParameter(string memory key, bytes32 value) internal {
        emit ParameterSet(key, key, _parameters[key] = value);
    }

}
