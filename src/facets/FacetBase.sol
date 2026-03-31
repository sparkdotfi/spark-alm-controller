// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IAccessControls } from "../interfaces/IAccessControls.sol";

import { ControllerSharedStorage } from "../ControllerSharedStorage.sol";

import { IFacetBase } from "./IFacetBase.sol";

abstract contract FacetBase is IFacetBase, ControllerSharedStorage, ReentrancyGuard {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant override RELAYER_ROLE       = keccak256("RELAYER");

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
