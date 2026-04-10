// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { IEnumerableIntegrations } from "./IEnumerableIntegrations.sol";

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

    function setIntegration(bytes32 id, Config calldata config) external;

    function removeIntegration(bytes32 id) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
