// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IMapleFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MapleCancelRedemption(address indexed mapleToken, uint256 shares);

    event MapleRequestRedemption(address indexed mapleToken, uint256 shares);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function cancelRedemption(address mapleToken, uint256 shares) external;

    function requestRedemption(address mapleToken, uint256 shares) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_REDEEM() external pure returns (bytes32);

}
