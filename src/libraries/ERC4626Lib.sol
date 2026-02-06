// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IERC4626Like {

    function deposit(uint256 amount, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    function asset() external view returns (address);

}

library ERC4626Lib {

    event MaxExchangeRateSet(address indexed token, uint256 maxExchangeRate);

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_4626_WITHDRAW");

    uint256 public constant EXCHANGE_RATE_PRECISION = 1e36;

    function setMaxExchangeRate(
        mapping (address => uint256) storage maxExchangeRates,
        address                              token,
        uint256                              shares,
        uint256                              maxExpectedAssets
    )
        external
    {
        require(token != address(0), "ERC4626Lib/token-zero-address");

        emit MaxExchangeRateSet(
            token,
            maxExchangeRates[token] = _getExchangeRate(shares, maxExpectedAssets)
        );
    }

    function deposit(
        address                              proxy,
        address                              token,
        uint256                              amount,
        uint256                              minSharesOut,
        mapping (address => uint256) storage maxExchangeRates,
        address                              rateLimits
    )
        external
        returns (uint256 shares)
    {
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, token, amount);

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(IERC4626Like(token).asset(), proxy, token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.deposit, (amount, proxy))
            ),
            (uint256)
        );

        require(shares >= minSharesOut, "ERC4626Lib/min-shares-out-not-met");

        require(
            _getExchangeRate(shares, amount) <= maxExchangeRates[token],
            "ERC4626Lib/exchange-rate-too-high"
        );
    }

    function withdraw(
        address proxy,
        address token,
        uint256 amount,
        uint256 maxSharesIn,
        address rateLimits
    )
        external
        returns (uint256 shares)
    {
        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, token, amount);

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.withdraw, (amount, proxy, proxy))
            ),
            (uint256)
        );

        require(shares <= maxSharesIn, "ERC4626Lib/shares-burned-too-high");

        _increaseRateLimit(rateLimits, LIMIT_DEPOSIT, token, amount);
    }

    function redeem(
        address proxy,
        address token,
        uint256 shares,
        uint256 minAssetsOut,
        address rateLimits
    )
        external
        returns (uint256 assets)
    {
        // Redeem shares for assets from the token, decode the resulting assets.
        // Assumes proxy has adequate token shares.
        assets = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.redeem, (shares, proxy, proxy))
            ),
            (uint256)
        );

        require(assets >= minAssetsOut, "ERC4626Lib/min-assets-out-not-met");

        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, token, assets);
        _increaseRateLimit(rateLimits, LIMIT_DEPOSIT,  token, assets);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, address token, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, token), amount);
    }

    function _increaseRateLimit(address rateLimits, bytes32 key, address token, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitIncrease(makeAddressKey(key, token), amount);
    }

    function _getExchangeRate(uint256 shares, uint256 assets) internal pure returns (uint256) {
        // Return 0 for zero assets first, to handle the valid case of 0 shares and 0 assets.
        if (assets == 0) return 0;

        // Zero shares with non-zero assets is invalid (infinite exchange rate).
        if (shares == 0) revert("ERC4626Lib/zero-shares");

        return (EXCHANGE_RATE_PRECISION * assets) / shares;
    }

}
