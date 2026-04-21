// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControl } from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { Address }       from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import { IALMProxyFreezable } from "./interfaces/IALMProxyFreezable.sol";

contract ALMProxyFreezable is IALMProxyFreezable, AccessControl {

    using Address for address;

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override FREEZER = keccak256("FREEZER");
    bytes32 public constant override RELAYER = keccak256("RELAYER");

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

    function removeRelayer(address relayer) external override onlyRole(FREEZER) {
        require(_revokeRole(RELAYER, relayer), "ALMProxyFreezable/not-live-relayer");

        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function doCall(address target, bytes calldata data)
        external
        override
        onlyRole(RELAYER)
        returns (bytes memory result)
    {
        result = target.functionCall(data);
    }

    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        override
        onlyRole(RELAYER)
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

}
