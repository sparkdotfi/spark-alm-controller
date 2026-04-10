// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IFacetBase
 * @notice Base interface inherited by all PAU facets. Defines shared roles, versioning,
 *         and access control errors.
 */
interface IFacetBase {

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    /// @notice Thrown when a caller lacks the required access control role.
    error AccessControlUnauthorizedAccount(address caller, bytes32 role);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Role identifier for the default admin (bytes32(0)).
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

    /// @notice Role identifier for relayer accounts authorized to execute facet operations.
    function RELAYER_ROLE() external pure returns (bytes32);

    /// @notice Semantic version string of the facet.
    function VERSION() external pure returns (string memory);

}
