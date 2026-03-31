// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";

contract AccessControls is IAccessControls, ReentrancyGuard, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        require(admin != address(0), ZeroAdmin());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** External Interactive Freezer Functions                                                 ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external override nonReentrant onlyRole(FREEZER_ROLE) {
        _revokeRole(RELAYER_ROLE, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

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
