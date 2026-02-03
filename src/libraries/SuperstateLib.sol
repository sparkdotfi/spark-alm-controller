// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IUSTBLike {

    function subscribe(uint256 inAmount, address stablecoin) external;

}

// NOTE: Argument names imply that this is only compatible with USTB and USDC.
library SuperstateLib {

    bytes32 public constant LIMIT_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function subscribe(
        address proxy,
        address rateLimits,
        address usdc,
        address ustb,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_SUBSCRIBE, usdcAmount);

        ApproveLib.approve(usdc, proxy, ustb, usdcAmount);

        IALMProxy(proxy).doCall(ustb, abi.encodeCall(IUSTBLike.subscribe, (usdcAmount, usdc)));
    }

}
