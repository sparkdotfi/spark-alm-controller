// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title  IAccessControls
 * @notice Role-based access control interface for PAU system, extending OpenZeppelin's
 *         AccessControlEnumerable with freezer and relayer roles.
 */
interface IAccessControls is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a freezer removes a relayer from the system.
     * @param  relayer Address of the relayer that was removed.
     */
    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the admin is the zero address.
    error ZeroAdmin();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Removes a relayer by revoking their RELAYER_ROLE. Only callable by a freezer.
     * @param  relayer Address of the relayer to remove.
     */
    function removeRelayer(address relayer) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Role identifier for freezer accounts that can remove relayers.
    function FREEZER_ROLE() external view returns (bytes32);

    /// @notice Role identifier for relayer accounts authorized to execute controller functions.
    function RELAYER_ROLE() external view returns (bytes32);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns true if the contract supports the given interface.
     * @param  interfaceId The 4-byte interface identifier (ERC-165).
     * @return isSupported True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool isSupported);

}
