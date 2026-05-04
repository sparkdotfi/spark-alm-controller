// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ISparkVaultFacet } from "./ISparkVaultFacet.sol";

interface ISparkVaultLike {

    function take(uint256 assetAmount) external;

}

contract SparkVaultFacet is ISparkVaultFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc ISparkVaultFacet
    function take(address sparkVault, uint256 assetAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(getTakeRateLimitKey(sparkVault), assetAmount);

        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            sparkVault,
            abi.encodeCall(ISparkVaultLike.take, (assetAmount))
        );

        emit SparkVaultTake(sparkVault, assetAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ISparkVaultFacet
    function getTakeRateLimitKey(address sparkVault) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_TAKE, sparkVault);
    }

}
