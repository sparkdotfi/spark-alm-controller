// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface ISparkVaultLike {

    function take(uint256 assetAmount) external;

}

library SparkVaultLib {

    bytes32 public constant LIMIT_TAKE = keccak256("LIMIT_SPARK_VAULT_TAKE");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function take(address proxy, address rateLimits, address sparkVault, uint256 assetAmount)
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_TAKE, sparkVault),
            assetAmount
        );

        IALMProxy(proxy).doCall(sparkVault, abi.encodeCall(ISparkVaultLike.take, (assetAmount)));
    }

}
