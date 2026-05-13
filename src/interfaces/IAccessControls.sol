// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title  IAccessControls
 * @notice Role-based access control interface for PAU system, extending OpenZeppelin's
 *         AccessControlEnumerable.
 */
interface IAccessControls is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the admin is the zero address.
    error ZeroAdmin();

    /**********************************************************************************************/
    /*** Interactive Admin Functions                                                            ***/
    /**********************************************************************************************/

    /**
     * @notice Sets the admin role for a given role.
     * @param role      The role to set the admin for.
     * @param adminRole The admin role for the given role.
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns true if the contract supports the given interface.
     * @param  interfaceId The 4-byte interface identifier (ERC-165).
     * @return isSupported True if the interface is supported, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
