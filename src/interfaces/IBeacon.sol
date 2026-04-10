// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IEnumerableIntegrations } from "./IEnumerableIntegrations.sol";

/**
 * @title  IBeacon
 * @notice Configuration registry for the PAU system. Stores integration configs (facet
 *         address and selector wiring) that Controllers sync from to build their dispatch tables.
 */
interface IBeacon is IAccessControlEnumerable, IEnumerableIntegrations {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the call selector is hardcoded.
    error CallSelectorHardcoded(bytes4 callSelector);

    /// @notice Thrown when an argument array is empty.
    error EmptyArray();

    /// @notice Thrown when the admin is the zero address.
    error ZeroAdmin();

    /// @notice Thrown when the facet is the zero address.
    error ZeroFacet();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Registers or updates an integration with its facet address and selector wires.
     * @param  id     Unique identifier for the integration.
     * @param  config Facet address and array of selector wires to register.
     */
    function setIntegration(bytes32 id, Config calldata config) external;

    /**
     * @notice Removes an integration and all of its selector dispatches.
     * @param  id Unique identifier of the integration to remove.
     */
    function removeIntegration(bytes32 id) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns true if the contract supports the given interface.
     * @param  interfaceId The 4-byte interface identifier (ERC-165).
     * @return isSupported True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool isSupported);

}
