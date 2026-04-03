// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControl } from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { Address }       from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import { IALMProxy } from "./interfaces/IALMProxy.sol";

contract ALMProxy is IALMProxy, AccessControl {

    using Address for address;

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override CONTROLLER = keccak256("CONTROLLER");

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** External Interactive Controller Functions                                              ***/
    /**********************************************************************************************/

    function doCall(address target, bytes calldata data)
        external
        override
        onlyRole(CONTROLLER)
        returns (bytes memory result)
    {
        result = target.functionCall(data);
    }

    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        override
        onlyRole(CONTROLLER)
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    function doDelegateCall(address target, bytes calldata data)
        external
        override
        onlyRole(CONTROLLER)
        returns (bytes memory result)
    {
        result = target.functionDelegateCall(data);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

}
