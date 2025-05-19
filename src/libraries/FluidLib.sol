// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IRateLimits} from "../interfaces/IRateLimits.sol";
import {IALMProxy} from "../interfaces/IALMProxy.sol";

import {RateLimitHelpers} from "../RateLimitHelpers.sol";

interface IFluidSmartLending is IERC20 {
    /// @dev This function allows users to deposit tokens in any proportion into the col pool
    /// @param token0Amt_ The amount of token0 to deposit
    /// @param token1Amt_ The amount of token1 to deposit
    /// @param minSharesAmt_ The minimum amount of shares the user expects to receive
    /// @param to_ Recipient of minted tokens. If to_ == address(0) then out tokens will be sent to msg.sender.
    /// @return amount_ The amount of tokens minted for the deposit
    /// @return shares_ The number of dex pool shares deposited
    function deposit(
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 minSharesAmt_,
        address to_
    ) external payable returns (uint256 amount_, uint256 shares_);

    /// @dev This function allows users to withdraw tokens in any proportion from the col pool
    /// @param token0Amt_ The amount of token0 to withdraw
    /// @param token1Amt_ The amount of token1 to withdraw
    /// @param maxSharesAmt_ The maximum number of shares the user is willing to burn
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender. If to_ == ADDRESS_DEAD then function will revert with shares_
    /// @return amount_ The number of tokens burned for the withdrawal
    /// @return shares_ The number of dex pool shares withdrawn
    function withdraw(
        uint256 token0Amt_,
        uint256 token1Amt_,
        uint256 maxSharesAmt_,
        address to_
    ) external returns (uint256 amount_, uint256 shares_);

    /// @dev This function allows users to withdraw a perfect amount of collateral liquidity
    /// @param shares_ The number of shares to withdraw. set to type(uint).max to withdraw maximum balance.
    /// @param minToken0Withdraw_ The minimum amount of token0 the user is willing to accept
    /// @param minToken1Withdraw_ The minimum amount of token1 the user is willing to accept
    /// @param to_ Recipient of withdrawn tokens. If to_ == address(0) then out tokens will be sent to msg.sender.
    /// @return amount_ amount_ of shares actually burnt
    /// @return token0Amt_ The amount of token0 withdrawn
    /// @return token1Amt_ The amount of token1 withdrawn
    function withdrawPerfect(
        uint256 shares_,
        uint256 minToken0Withdraw_,
        uint256 minToken1Withdraw_,
        address to_
    )
        external
        returns (uint256 amount_, uint256 token0Amt_, uint256 token1Amt_);

    function TOKEN0() external returns (address);
    function TOKEN1() external returns (address);
}

library FluidLib {
    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct DepositSmartLendingParams {
        IALMProxy proxy;
        IRateLimits rateLimits;
        address smartLending;
        uint256 token0Amount;
        uint256 token1Amount;
        uint256 minShares;
        bytes32 depositSLRateLimitId;
    }

    struct WithdrawSmartLendingParams {
        IALMProxy proxy;
        IRateLimits rateLimits;
        address smartLending;
        uint256 token0Amount;
        uint256 token1Amount;
        uint256 maxSLTokens; // maximum smart lending tokens amount allowed to burn
        bytes32 withdrawSLRateLimitId;
    }

    struct WithdrawPerfectSmartLendingParams {
        IALMProxy proxy;
        IRateLimits rateLimits;
        address smartLending;
        uint256 sLTokensAmount; // smart lending tokens amount to burn
        uint256 minToken0Amount;
        uint256 minToken1Amount;
        bytes32 withdrawSLRateLimitId;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function depositSmartLending(
        DepositSmartLendingParams calldata params
    ) external returns (uint256 shares) {
        // only supports ERC20s. native ETH support can be added if needed.

        IFluidSmartLending smartLending = IFluidSmartLending(
            params.smartLending
        );

        if (params.token0Amount > 0) {
            address token0 = smartLending.TOKEN0();

            params.rateLimits.triggerRateLimitDecrease(
                RateLimitHelpers.makeAssetDestinationKey(
                    params.depositSLRateLimitId,
                    token0,
                    params.smartLending
                ),
                params.token0Amount
            );

            // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
            _approve(
                params.proxy,
                token0,
                params.smartLending,
                params.token0Amount
            );
        }
        if (params.token1Amount > 0) {
            address token1 = smartLending.TOKEN1();

            params.rateLimits.triggerRateLimitDecrease(
                RateLimitHelpers.makeAssetDestinationKey(
                    params.depositSLRateLimitId,
                    token1,
                    params.smartLending
                ),
                params.token1Amount
            );

            // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
            _approve(
                params.proxy,
                token1,
                params.smartLending,
                params.token1Amount
            );
        }

        (, shares) = abi.decode(
            params.proxy.doCall(
                params.smartLending,
                abi.encodeCall(
                    smartLending.deposit,
                    (
                        params.token0Amount,
                        params.token1Amount,
                        params.minShares,
                        address(params.proxy)
                    )
                )
            ),
            (uint256, uint256)
        );
    }

    function withdrawSmartLending(
        WithdrawSmartLendingParams calldata params
    ) external returns (uint256 shares) {
        IFluidSmartLending smartLending = IFluidSmartLending(
            params.smartLending
        );

        bytes32 rateLimitKey = RateLimitHelpers.makeAssetKey(
            params.withdrawSLRateLimitId,
            params.smartLending
        );

        params.rateLimits.triggerRateLimitDecrease(
            rateLimitKey,
            params.maxSLTokens
        );

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        (shares, ) = abi.decode(
            params.proxy.doCall(
                params.smartLending,
                abi.encodeCall(
                    smartLending.withdraw,
                    (
                        params.token0Amount,
                        params.token1Amount,
                        params.maxSLTokens,
                        address(params.proxy)
                    )
                )
            ),
            (uint256, uint256)
        );

        uint256 sharesDiff = params.maxSLTokens - shares; // actual withdrawn SL tokens is always <= maxSLTokens
        if (sharesDiff > 0) {
            params.rateLimits.triggerRateLimitIncrease(
                rateLimitKey,
                sharesDiff
            );
        }
    }

    function withdrawPerfectSmartLending(
        WithdrawPerfectSmartLendingParams calldata params
    ) external returns (uint256 shares) {
        IFluidSmartLending smartLending = IFluidSmartLending(
            params.smartLending
        );

        bytes32 rateLimitKey = RateLimitHelpers.makeAssetKey(
            params.withdrawSLRateLimitId,
            params.smartLending
        );

        params.rateLimits.triggerRateLimitDecrease(
            rateLimitKey,
            params.sLTokensAmount == type(uint256).max
                ? IERC20(params.smartLending).balanceOf(address(params.proxy))
                : params.sLTokensAmount
        );

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        (shares, , ) = abi.decode(
            params.proxy.doCall(
                params.smartLending,
                abi.encodeCall(
                    smartLending.withdrawPerfect,
                    (
                        params.sLTokensAmount,
                        params.minToken0Amount,
                        params.minToken1Amount,
                        address(params.proxy)
                    )
                )
            ),
            (uint256, uint256, uint256)
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _approve(
        IALMProxy proxy,
        address token,
        address spender,
        uint256 amount
    ) internal {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }
}
