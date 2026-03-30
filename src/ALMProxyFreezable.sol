// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControl } from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import { Address }       from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract ALMProxyFreezable is AccessControl {

    using Address for address;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant RELAYER = keccak256("RELAYER");
    bytes32 public constant FREEZER = keccak256("FREEZER");

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function doCall(address target, bytes memory data)
        external
        onlyRole(RELAYER)
        returns (bytes memory result)
    {
        result = target.functionCall(data);
    }

    function doCallWithValue(address target, bytes memory data, uint256 value)
        external
        payable
        onlyRole(RELAYER)
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
