// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IFarmLike {

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

}

library FarmLib {

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_FARM_WITHDRAW");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(address proxy, address rateLimits, address token, address farm, uint256 amount)
        external
    {
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, farm, amount);

        ApproveLib.approve(token, proxy, farm, amount);

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.stake, (amount)));
    }

    function withdraw(address proxy, address rateLimits, address farm, uint256 amount) external {
        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, farm, amount);

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.withdraw, (amount)));

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.getReward, ()));
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, address farm, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, farm), amount);
    }

}
