// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { RolesLib } from '../libraries/RolesLib.sol';

contract Roles {

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(address admin_) external {
        RolesLib.grantRole(RolesLib.ADMIN_ROLE, admin_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function grantRole(bytes32 role_, address account_) external {
        _revertIfNotAdmin();
        RolesLib.grantRole(role_, account_);
    }

    function revokeRole(bytes32 role_, address account_) external {
        _revertIfNotAdmin();
        RolesLib.revokeRole(role_, account_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external pure returns (bytes32 adminRole_) {
        return RolesLib.ADMIN_ROLE;
    }

    function hasRole(bytes32 role_, address account_) public view returns (bool hasRole_) {
        return RolesLib.hasRole(role_, account_);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(RolesLib.ADMIN_ROLE, msg.sender);
    }

}
