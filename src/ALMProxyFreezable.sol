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

    bytes32 public constant override ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant override FREEZER_ROLE   = keccak256("FREEZER_ROLE");

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

    function removeAllocator(address allocator) external override onlyRole(FREEZER_ROLE) {
        require(_revokeRole(ALLOCATOR_ROLE, allocator), "ALMProxyFreezable/not-live-allocator");

        emit AllocatorRemoved(allocator);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    function doCall(address target, bytes calldata data)
        external
        override
        onlyRole(ALLOCATOR_ROLE)
        returns (bytes memory result)
    {
        result = target.functionCall(data);
    }

    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        override
        onlyRole(ALLOCATOR_ROLE)
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

}
