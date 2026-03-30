// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { ISparkVaultFacet } from "./ISparkVaultFacet.sol";

interface ISparkVaultLike {

    function take(uint256 assetAmount) external;

}

contract SparkVaultFacet is ISparkVaultFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function take(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_TAKE, sparkVault),
            assetAmount
        );

        IALMProxy($.proxy).doCall(
            sparkVault,
            abi.encodeCall(ISparkVaultLike.take, (assetAmount))
        );
    }

}
