// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressAddressKey } from "../RateLimitHelpers.sol";

library TransferAssetLib {

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_ASSET_TRANSFER");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transfer(
        address proxy,
        address rateLimits,
        address asset,
        address destination,
        uint256 amount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(LIMIT_TRANSFER, asset, destination),
            amount
        );

        bytes memory returnData = IALMProxy(proxy).doCall(
            asset,
            abi.encodeCall(IERC20.transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "TransferAssetLib/transfer-failed"
        );
    }

}
