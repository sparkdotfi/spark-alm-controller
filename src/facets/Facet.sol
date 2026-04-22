// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    ReentrancyGuardUpgradeable
} from "../../lib/oz-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import { IAccessControls } from "../interfaces/IAccessControls.sol";

import { ControllerSharedStorage } from "../ControllerSharedStorage.sol";

import { IFacet } from "./IFacet.sol";

abstract contract Facet is IFacet, ControllerSharedStorage, ReentrancyGuardUpgradeable {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IFacet
    bytes32 public constant override DEFAULT_ADMIN_ROLE = 0x00;

    /// @inheritdoc IFacet
    bytes32 public constant override RELAYER_ROLE = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyRole(bytes32 role) {
        address accessControls = _getSharedControllerStorage().accessControls;

        require(
            IAccessControls(accessControls).hasRole(role, msg.sender),
            AccessControlUnauthorizedAccount(msg.sender, role)
        );

        _;
    }

}
