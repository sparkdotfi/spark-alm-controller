// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxy } from "./ALMProxy.sol";

contract ALMProxyFreezable is ALMProxy {

    event ControllerRemoved(address indexed controller);

    bytes32 public constant FREEZER = keccak256("FREEZER");

    constructor(address admin) ALMProxy(admin) {}

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function removeController(address controller) external onlyRole(FREEZER) {
        _revokeRole(CONTROLLER, controller);
        emit ControllerRemoved(controller);
    }

}
