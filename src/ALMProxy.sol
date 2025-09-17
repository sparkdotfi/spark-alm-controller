// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import { Address }       from "openzeppelin-contracts/contracts/utils/Address.sol";

import { IALMProxy } from "./interfaces/IALMProxy.sol";

contract ALMProxy is IALMProxy, AccessControl {

    using Address for address;

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public override constant CONTROLLER = keccak256("CONTROLLER");

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function doCall(address target, bytes memory data)
        external override onlyRole(CONTROLLER) returns (bytes memory result)
    {
        result = target.functionCall(data);
    }

    function doCallWithValue(address target, bytes memory data, uint256 value)
        external payable override onlyRole(CONTROLLER) returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    function doDelegateCall(address target, bytes memory data)
        external override onlyRole(CONTROLLER) returns (bytes memory result)
    {
        result = target.functionDelegateCall(data);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
