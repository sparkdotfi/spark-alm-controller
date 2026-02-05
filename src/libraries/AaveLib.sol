// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IATokenWithPoolLike {

    function POOL() external view returns(address);

    function UNDERLYING_ASSET_ADDRESS() external view returns(address);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IPoolLike {

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    )
        external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

}

library AaveLib {

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_AAVE_WITHDRAW");

    function deposit(
        address proxy,
        address aToken,
        uint256 amount,
        uint256 maxSlippage,
        address rateLimits
    )
        external
    {
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, aToken, amount);

        require(maxSlippage != 0, "AaveLib/max-slippage-not-set");

        address underlying = IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS();
        address pool       = IATokenWithPoolLike(aToken).POOL();

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        ApproveLib.approve(underlying, proxy, pool, amount);

        uint256 aTokenBalance = IERC20Like(aToken).balanceOf(proxy);

        // Deposit underlying into Aave pool, proxy receives aTokens
        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(IPoolLike(pool).supply, (underlying, amount, proxy, 0))
        );

        uint256 newATokens = IERC20Like(aToken).balanceOf(proxy) - aTokenBalance;

        require(newATokens >= amount * maxSlippage / 1e18, "AaveLib/slippage-too-high");
    }

    function withdraw(address proxy,address aToken,uint256 amount,address rateLimits)
        external
        returns (uint256 amountWithdrawn)
    {
        address pool = IATokenWithPoolLike(aToken).POOL();

        // Withdraw underlying from Aave pool, decode resulting amount withdrawn.
        // Assumes proxy has adequate aTokens.
        amountWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(
                    IPoolLike(pool).withdraw,
                    (IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS(), amount, proxy)
                )
            ),
            (uint256)
        );

        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, aToken, amountWithdrawn);
        _increaseRateLimit(rateLimits, LIMIT_DEPOSIT,  aToken, amountWithdrawn);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, address aToken, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, aToken), amount);
    }

    function _increaseRateLimit(address rateLimits, bytes32 key, address aToken, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitIncrease(makeAddressKey(key, aToken), amount);
    }

}
