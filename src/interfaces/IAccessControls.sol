// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title  IAccessControls
 * @notice Role-based access control interface for PAU system, extending OpenZeppelin's
 *         AccessControlEnumerable, with per-role admins for role revocation.
 */
interface IAccessControls is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /**
     * @notice Thrown when the account is not the role admin or the default admin.
     * @param  account   The account calling the function.
     * @param  role      The role that the account is not the admin for.
     * @param  roleAdmin The role that is the admin for the given role.
     */
    error NotRoleAdminOrDefaultAdmin(address account, bytes32 role, bytes32 roleAdmin);

    /**
     * @notice Thrown when attempting to revoke a role from an account that does not have that role.
     * @param  account The account that does not have the given role.
     * @param  role    The role that the account does not have.
     */
    error RoleNotGranted(address account, bytes32 role);

    /// @notice Thrown when the admin is the zero address.
    error ZeroAdmin();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Sets the role that can revoke a given role.
     * @param  role        The role to set the revoker for.
     * @param  revokerRole The role that can revoke the given role.
     */
    function setRoleRevoker(bytes32 role, bytes32 revokerRole) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the role that can revoke a given role.
     * @param  role        The role to get the revoker for.
     * @return revokerRole The role that can revoke the given role.
     */
    function getRoleRevoker(bytes32 role) external view returns (bytes32);

    /**
     * @notice Returns true if the contract supports the given interface.
     * @param  interfaceId The 4-byte interface identifier (ERC-165).
     * @return isSupported True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool isSupported);

}
