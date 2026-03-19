// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IPSM3Like {

    function deposit(address asset, address receiver, uint256 assetsToDeposit)
        external
        returns (uint256 newShares);

    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external
        returns (uint256 assetsWithdrawn);

}

library PSM3Lib {

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_PSM_WITHDRAW");

    function deposit(
        address proxy,
        address rateLimits,
        address psm,
        address asset,
        uint256 amount
    )
        external
        returns (uint256 shares)
    {
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, asset, amount);

        // Approve `asset` to PSM from the proxy (assumes the proxy has enough `asset`).
        ApproveLib.approve(asset, proxy, psm, amount);

        // Deposit `amount` of `asset` in the PSM, decode the result to get `shares`.
        return abi.decode(
            IALMProxy(proxy).doCall(psm, abi.encodeCall(IPSM3Like.deposit, (asset, proxy, amount))),
            (uint256)
        );
    }

    function withdraw(
        address proxy,
        address rateLimits,
        address psm,
        address asset,
        uint256 maxAmount
    )
        external
        returns (uint256 assetsWithdrawn)
    {
        // Withdraw up to `maxAmount` of `asset` in the PSM, decode the result to get
        // `assetsWithdrawn` (assumes the proxy has enough PSM shares).
        // NOTE: Rate limited at end of function, so cannot return here.
        assetsWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                psm,
                abi.encodeCall(IPSM3Like.withdraw, (asset, proxy, maxAmount))
            ),
            (uint256)
        );

        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, asset, assetsWithdrawn);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, address asset, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, asset), amount);
    }

}
