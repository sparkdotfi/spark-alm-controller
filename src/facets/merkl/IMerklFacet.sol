// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IMerklFacet
 * @notice PAU facet for toggling operators on a Merkl reward distributor. Operators can claim
 *         Merkl rewards on behalf of the proxy.
 */
interface IMerklFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an operator is toggled on the Merkl distributor.
     * @param  distributor Address of the Merkl reward distributor contract.
     * @param  operator    Address of the operator being toggled.
     */
    event MerklToggleOperator(address indexed distributor, address indexed operator);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Toggles an operator's authorization on the Merkl distributor for the proxy.
     * @param  distributor Address of the Merkl reward distributor contract.
     * @param  operator    Address of the operator to toggle.
     */
    function toggleOperator(address distributor, address operator) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived toggle operator rate limit key for a distributor and operator.
     * @param  distributor Address of the Merkl reward distributor contract.
     * @param  operator    Address of the operator being toggled.
     * @return key         Derived rate limit key.
     */
    function getToggleOperatorRateLimitKey(address distributor, address operator)
        external
        pure
        returns (bytes32 key);

}
