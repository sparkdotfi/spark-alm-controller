// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { AccessControl }  from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";

contract AccessControls is IAccessControls, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyRoleAdminOrDefaultAdmin(bytes32 role) {
        bytes32 roleAdmin = getRoleAdmin(role);

        require(
            hasRole(roleAdmin, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            NotRoleAdminOrDefaultAdmin(msg.sender, role, roleAdmin)
        );

        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        require(admin != address(0), ZeroAdmin());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /// @inheritdoc IAccessControl
    function grantRole(bytes32 role, address account)
        public
        override(IAccessControl, AccessControl)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(role, account);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 role, address account)
        public
        override(IAccessControl, AccessControl)
        onlyRoleAdminOrDefaultAdmin(role)
    {
        require(_revokeRole(role, account), RoleNotGranted(account, role));
    }

    /// @inheritdoc IAccessControls
    function setRoleRevoker(bytes32 role, bytes32 revokerRole)
        public
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setRoleAdmin(role, revokerRole);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IAccessControls
    function getRoleRevoker(bytes32 role) external view override returns (bytes32) {
        return getRoleAdmin(role);
    }

    /// @inheritdoc IAccessControls
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IAccessControls, AccessControlEnumerable)
        returns (bool)
    {
        return
            interfaceId == type(IAccessControls).interfaceId ||
            super.supportsInterface(interfaceId);
    }

}
