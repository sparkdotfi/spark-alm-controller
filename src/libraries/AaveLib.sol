// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken } from "../../lib/aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool }   from "../../lib/aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {

    function POOL() external view returns(address);

}

library AaveLib {

    function deposit(
        address proxy,
        address aToken,
        uint256 amount,
        uint256 maxSlippage,
        address rateLimits,
        bytes32 rateLimitId
    ) external {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(rateLimitId, aToken),
            amount
        );

        require(maxSlippage != 0, "MC/max-slippage-not-set");

        address underlying = IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS();
        address pool       = IATokenWithPool(aToken).POOL();

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        ApproveLib.approve(underlying, proxy, pool, amount);

        uint256 aTokenBalance = IERC20(aToken).balanceOf(proxy);

        // Deposit underlying into Aave pool, proxy receives aTokens
        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(IPool(pool).supply, (underlying, amount, proxy, 0))
        );

        uint256 newATokens = IERC20(aToken).balanceOf(proxy) - aTokenBalance;

        require(
            newATokens >= amount * maxSlippage / 1e18,
            "MC/slippage-too-high"
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function withdraw(
        address proxy,
        address aToken,
        uint256 amount,
        address rateLimits,
        bytes32 rateLimitWithdrawId,
        bytes32 rateLimitDepositId
    ) external returns (uint256 amountWithdrawn) {
        address pool = IATokenWithPool(aToken).POOL();

        // Withdraw underlying from Aave pool, decode resulting amount withdrawn.
        // Assumes proxy has adequate aTokens.
        amountWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(
                    IPool(pool).withdraw,
                    (IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS(), amount, proxy)
                )
            ),
            (uint256)
        );

        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(rateLimitWithdrawId, aToken),
            amountWithdrawn
        );

        IRateLimits(rateLimits).triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(rateLimitDepositId, aToken),
            amountWithdrawn
        );
    }

}
