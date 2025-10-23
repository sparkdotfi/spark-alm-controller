// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { RolesLib } from '../libraries/RolesLib.sol';

contract RoleRevoker {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event RoleRevoker_AdminRoleSet(bytes32 indexed adminRole);

    event RoleRevoker_RoleRevokerRoleSet(bytes32 indexed roleRevokerRole);

    event RoleRevoker_RevokableRoleSet(address indexed setter, bytes32 indexed role, bool isRevokable);

    event RoleRevoker_RoleRevoked(address indexed revoker, bytes32 indexed role, address indexed account);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error RoleRevoker_RoleNotRevokable(bytes32 role);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.RoleRevoker
     * @notice The UUPS storage for the RoleRevoker facet.
     */
    struct RoleRevokerStorage {
        bytes32 adminRole;
        bytes32 roleRevokerRole;
        mapping(bytes32 role => bool isRevokable) revokableRoles;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.RoleRevoker')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ROLE_REVOKER_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a03; // TODO: Update this.

    function _getRoleRevokerStorage() internal pure returns (RoleRevokerStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _ROLE_REVOKER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(bytes32 adminRole_, bytes32 roleRevokerRole_) external {
        emit RoleRevoker_AdminRoleSet(_getRoleRevokerStorage().adminRole = adminRole_);
        emit RoleRevoker_RoleRevokerRoleSet(_getRoleRevokerStorage().roleRevokerRole = roleRevokerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function setRevokableRole(bytes32 role_, bool isRevokable_) external {
        revertIfNotAdmin();
        emit RoleRevoker_RevokableRoleSet(msg.sender, role_, isRevokable_);
        _getRoleRevokerStorage().revokableRoles[role_] = isRevokable_;
    }

    function revoke(bytes32 role_, address account_) external {
        revertIfNotRoleRevoker();

        if (!_getRoleRevokerStorage().revokableRoles[role_]) revert RoleRevoker_RoleNotRevokable(role_);

        RolesLib.revokeRole(role_, account_);

        emit RoleRevoker_RoleRevoked(msg.sender, role_, account_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getRoleRevokerStorage().adminRole;
    }

    function roleRevokerRole() external view returns (bytes32 roleRevokerRole_) {
        return _getRoleRevokerStorage().roleRevokerRole;
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getRoleRevokerStorage().adminRole, msg.sender);
    }

    function revertIfNotRoleRevoker() internal view {
        RolesLib.revertIfNotAuthorized(_getRoleRevokerStorage().roleRevokerRole, msg.sender);
    }
}
