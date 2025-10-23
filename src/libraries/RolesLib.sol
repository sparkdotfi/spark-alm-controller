// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library RolesLib {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event RolesLib_RoleGranted(address indexed grantor, bytes32 indexed role, address indexed account);

    event RolesLib_RoleRevoked(address indexed revoker, bytes32 indexed role, address indexed account);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error Roles_NotAuthorized(address account, bytes32 role);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.Roles
     * @notice The UUPS storage for the Roles facet.
     */
    struct RolesStorage {
        mapping(bytes32 role => mapping(address account => bool hasRole)) roleAssignments;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.Roles')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant ROLES_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a01; // TODO: Update this.

    function getRolesStorage() internal pure returns (RolesStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := ROLES_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant ADMIN_ROLE = 'ADMIN';

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function grantRole(bytes32 role_, address account_) internal {
        getRolesStorage().roleAssignments[role_][account_] = true;
        emit RolesLib_RoleGranted(msg.sender, role_, account_);
    }

    function revokeRole(bytes32 role_, address account_) internal {
        getRolesStorage().roleAssignments[role_][account_] = false;
        emit RolesLib_RoleRevoked(msg.sender, role_, account_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function hasRole(bytes32 role_, address account_) internal view returns (bool hasRole_) {
        return getRolesStorage().roleAssignments[role_][account_];
    }

    function revertIfNotAuthorized(bytes32 role_, address account_) internal view {
        if (!hasRole(role_, account_)) revert Roles_NotAuthorized(account_, role_);
    }

}
