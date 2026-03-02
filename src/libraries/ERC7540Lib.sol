// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IERC4626Like {

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    function asset() external view returns (address);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function maxMint(address receiver) external view returns (uint256 maxShares);

    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

}

interface IERC7540Like {

    function requestDeposit(uint256 assets, address controller, address owner)
        external
        returns (uint256 requestId);

    function requestRedeem(uint256 shares, address controller, address owner)
        external
        returns (uint256 requestId);

}

library ERC7540Lib {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant LIMIT_REDEEM  = keccak256("LIMIT_7540_REDEEM");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function requestDeposit(address proxy, address rateLimits, address token, uint256 amount) external {
        // Note that whitelist is done by rate limits.
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, token, amount);

        // Approve asset to vault from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(IERC4626Like(token).asset(), proxy, token, amount);

        // Submit deposit request by transferring assets
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC7540Like.requestDeposit, (amount, proxy, proxy))
        );
    }

    function claimDeposit(address proxy, address rateLimits, address token) external {
        _rateLimitExists(rateLimits, makeAddressKey(LIMIT_DEPOSIT, token));

        uint256 shares = IERC4626Like(token).maxMint(proxy);

        // Claim shares from the vault to the proxy
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC4626Like.mint, (shares, proxy)));
    }

    function requestRedeem(address proxy, address rateLimits, address token, uint256 shares)
        external
    {
        _decreaseRateLimit(
            rateLimits,
            LIMIT_REDEEM,
            token,
            IERC4626Like(token).convertToAssets(shares)
        );

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC7540Like.requestRedeem, (shares, proxy, proxy))
        );
    }

    function claimRedeem(address proxy, address rateLimits, address token) external {
        _rateLimitExists(rateLimits, makeAddressKey(LIMIT_REDEEM, token));

        uint256 assets = IERC4626Like(token).maxWithdraw(proxy);

        // Claim assets from the vault to the proxy
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC4626Like.withdraw, (assets, proxy, proxy))
        );
    }

    /**********************************************************************************************/
    /*** Internal view/pure functions                                                           ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address rateLimits, bytes32 key, address token, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, token), amount);
    }

    function _rateLimitExists(address rateLimits, bytes32 key) internal view {
        require(
            IRateLimits(rateLimits).getRateLimitData(key).maxAmount > 0,
            "ERC7540Lib/invalid-action"
        );
    }

}
