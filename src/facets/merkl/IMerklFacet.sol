// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IMerklFacet
 * @notice PAU facet for toggling operators on the Merkl reward distributor. Operators can claim
 *         Merkl rewards on behalf of the proxy.
 */
interface IMerklFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when the address of the Merkl reward distributor contract is set.
     * @param  distributor Address of the Merkl reward distributor contract.
     */
    event MerklDistributorSet(address indexed distributor);

    /**
     * @notice Emitted when an operator is toggled on the Merkl distributor.
     * @param  operator Address of the operator being toggled.
     */
    event MerklToggleOperator(address indexed operator);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Sets the address of the Merkl reward distributor contract.
     * @param  distributor Address of the Merkl reward distributor contract.
     */
    function setDistributor(address distributor) external;

    /**
     * @notice Toggles an operator's authorization on the Merkl distributor for the proxy.
     * @param  operator Address of the operator to toggle.
     */
    function toggleOperator(address operator) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Address of the Merkl reward distributor contract.
    function distributor() external view returns (address);

}
