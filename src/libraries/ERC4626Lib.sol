// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library ERC4626Lib {

    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e36;

    function deposit(
        address proxy,
        address token,
        uint256 amount,
        uint256 minSharesOut,
        uint256 maxExchangeRate,
        address rateLimits,
        bytes32 rateLimitId
    ) external returns (uint256 shares) {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(rateLimitId, token),
            amount
        );

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(IERC4626(token).asset(), proxy, token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626(token).deposit, (amount, proxy))
            ),
            (uint256)
        );

        require(shares >= minSharesOut, "MC/min-shares-out-not-met");

        require(getExchangeRate(shares, amount) <= maxExchangeRate, "MC/exchange-rate-too-high");
    }

    function withdraw(
        address proxy,
        address token,
        uint256 amount,
        uint256 maxSharesIn,
        address rateLimits,
        bytes32 withdrawRateLimitId,
        bytes32 depositRateLimitId
    ) external returns (uint256 shares) {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(withdrawRateLimitId, token),
            amount
        );

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626(token).withdraw, (amount, proxy, proxy))
            ),
            (uint256)
        );

        require(shares <= maxSharesIn, "MC/max-shares-in-not-met");

        IRateLimits(rateLimits).triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(depositRateLimitId, token),
            amount
        );
    }

    function redeem(
        address proxy,
        address token,
        uint256 shares,
        uint256 minAssetsOut,
        address rateLimits,
        bytes32 withdrawRateLimitId,
        bytes32 depositRateLimitId
    ) external returns (uint256 assets) {
        // Redeem shares for assets from the token, decode the resulting assets.
        // Assumes proxy has adequate token shares.
        assets = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626(token).redeem, (shares, proxy, proxy))
            ),
            (uint256)
        );

        require(assets >= minAssetsOut, "MC/min-assets-out-not-met");

        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(withdrawRateLimitId, token),
            assets
        );

        IRateLimits(rateLimits).triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(depositRateLimitId, token),
            assets
        );
    }

    function getExchangeRate(uint256 shares, uint256 assets) public pure returns (uint256) {
        // Return 0 for zero assets first, to handle the valid case of 0 shares and 0 assets.
        if (assets == 0) return 0;

        // Zero shares with non-zero assets is invalid (infinite exchange rate).
        if (shares == 0) revert("MC/zero-shares");

        return (EXCHANGE_RATE_PRECISION * assets) / shares;
    }

}
