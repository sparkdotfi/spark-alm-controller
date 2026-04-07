// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IFacetBase {

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error AccessControlUnauthorizedAccount(address caller, bytes32 role);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

    function RELAYER_ROLE() external pure returns (bytes32);

    function VERSION() external pure returns (string memory);

}
