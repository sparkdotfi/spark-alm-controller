// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IOTCBuffer is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Approves `allowance` of `asset`.
     * @param  asset     Asset address.
     * @param  allowance Amount of allowance.
     */
    function approve(address asset, uint256 allowance) external;

    /**
     * @notice Initializes the OTC buffer.
     * @param  admin    Admin address.
     * @param  almProxy ALM proxy address.
     */
    function initialize(address admin, address almProxy) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice ALM proxy address.
     */
    function almProxy() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns whether the interface is supported.
     * @param  interfaceId Interface ID.
     * @return isSupported True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool isSupported);

}
