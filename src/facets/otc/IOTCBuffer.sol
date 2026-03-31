// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IOTCBuffer is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function approve(address asset, uint256 allowance) external;

    function initialize(address admin, address almProxy) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function almProxy() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
