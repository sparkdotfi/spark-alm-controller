// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ISparkVaultFacet
 * @notice PAU facet for taking (drawing) assets from a Spark vault.
 */
interface ISparkVaultFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when assets are taken from a Spark vault.
     * @param  sparkVault  Address of the Spark vault.
     * @param  assetAmount Amount of assets taken.
     */
    event SparkVaultTake(address indexed sparkVault, uint256 assetAmount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Takes (draws) assets from a Spark vault to the proxy.
     * @param  sparkVault  Address of the Spark vault.
     * @param  assetAmount Amount of assets to take.
     */
    function take(address sparkVault, uint256 assetAmount) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived take rate limit key for a Spark vault.
     * @param  sparkVault Address of the Spark vault.
     * @return key        Derived rate limit key.
     */
    function getTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

}
