// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { ApproveLib }  from "./ApproveLib.sol";

interface IPendleRouterLike {

    enum SwapType {
        NONE,
        KYBERSWAP,
        ODOS,
        // ETH_WETH not used in Aggregator
        ETH_WETH,
        OKX,
        ONE_INCH,
        PARASWAP,
        RESERVE_2,
        RESERVE_3,
        RESERVE_4,
        RESERVE_5
    }

    struct SwapData {
        SwapType swapType;
        address  extRouter;
        bytes    extCalldata;
        bool     needScale;
    }

    struct TokenOutput {
        address  tokenOut;
        uint256  minTokenOut;
        address  tokenRedeemSy;
        address  pendleSwap;
        SwapData swapData;
    }

    function redeemPyToToken(
        address              receiver,
        address              yt,
        uint256              netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);

}

interface IPendleMarketLike {

    function readTokens() external view returns (address sy, address pt, address yt);

    function isExpired() external view returns (bool);

}

interface ISYLike {

    function yieldToken() external view returns (address);

}

interface IYTLike {

    function pyIndexCurrent() external returns (uint256);

}

library PendleLib {

    bytes32 public constant LIMIT_REDEEM = keccak256("LIMIT_PENDLE_PT_REDEEM");

    // NOTE: DO NOT use for markets with non-standard SYs, without additional testing
    //       targeting each onboarded non-standard SY market.
    //       (Non-standard SYs: ePENDLE, mPENDLE, aTokens (aUSDC, aUSDT))
    function redeem(
        address proxy,
        address rateLimits,
        address market,
        address router,
        uint256 pyAmountIn,
        uint256 minAmountOut
    ) external {
        require(router != address(0),                  "PendleLib/pendle-router-not-set");
        require(IPendleMarketLike(market).isExpired(), "PendleLib/market-not-expired");
        require(minAmountOut != 0,                     "PendleLib/min-amount-out-not-set");

        ( address sy, address pt, address yt ) = IPendleMarketLike(market).readTokens();

        address tokenOut = ISYLike(sy).yieldToken();

        // expected to receive full amount, but the buffer is subtracted
        // to avoid reverts due to potential rounding errors
        uint256 minTokenOut = pyAmountIn * 1e18 / IYTLike(yt).pyIndexCurrent() - 5;

        ApproveLib.approve(pt, proxy, router, pyAmountIn);

        uint256 tokenOutAmountBefore = IERC20(tokenOut).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            router,
            abi.encodeCall(
                IPendleRouterLike.redeemPyToToken, (
                    proxy,
                    yt,
                    pyAmountIn,
                    _createSimpleTokenOutput(tokenOut, minTokenOut)
                )
            )
        );

        uint256 totalTokenOutAmount = IERC20(tokenOut).balanceOf(proxy) - tokenOutAmountBefore;

        require(totalTokenOutAmount >= minAmountOut, "PendleLib/min-amount-not-met");

        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REDEEM, market),
            totalTokenOutAmount
        );

    }

    function _createSimpleTokenOutput(address tokenOut, uint256 minTokenOut)
        internal
        pure
        returns (IPendleRouterLike.TokenOutput memory)
    {
        IPendleRouterLike.SwapData memory swapData;

        return IPendleRouterLike.TokenOutput({
            tokenOut      : tokenOut,
            minTokenOut   : minTokenOut,
            tokenRedeemSy : tokenOut,
            pendleSwap    : address(0),
            swapData      : swapData
        });
    }

}
