// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { ERC20Lib }    from "../libraries/common/ERC20Lib.sol";

import {
    IPendleMarket,
    IPendleRouter,
    ISY,
    IYT,
    SwapData,
    TokenOutput
} from "../interfaces/PendleInterfaces.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library PendleLib {

    struct RedeemPendlePTParams {
        IALMProxy     proxy;
        IRateLimits   rateLimits;
        IPendleMarket pendleMarket;
        address       pendleRouter;
        bytes32       rateLimitId;
        uint256       pyAmountIn;
        uint256       minAmountOut;
    }

    function createEmptySwapData() internal pure returns (SwapData memory emptySwapData) {}

    function createSimpleTokenOutput(address tokenOut, uint256 minTokenOut) internal pure returns (TokenOutput memory simpleTokenOutput) {
        simpleTokenOutput = TokenOutput({
            tokenOut      : tokenOut,
            minTokenOut   : minTokenOut,
            tokenRedeemSy : tokenOut,
            pendleSwap    : address(0),
            swapData      : createEmptySwapData()
        });
    }

    function redeemPendlePT(RedeemPendlePTParams memory params) external {
        require(params.pendleMarket.isExpired(), "PendleLib/market-not-expired");
        require(params.minAmountOut != 0,        "PendleLib/min-amount-out-not-set");

        (address sy, address pt, address yt) = params.pendleMarket.readTokens();

        address tokenOut = ISY(sy).yieldToken();

        uint256 pyIndexCurrent = IYT(yt).pyIndexCurrent();

        // expected to receive full amount, but the buffer is subtracted
        // to avoid reverts due to potential rounding errors
        uint256 minTokenOut = params.pyAmountIn * 1e18 / pyIndexCurrent - 5;

        ERC20Lib.approve(params.proxy, pt, params.pendleRouter, params.pyAmountIn);

        uint256 tokenOutAmountBefore = IERC20(tokenOut).balanceOf(address(params.proxy));

        params.proxy.doCall(
            params.pendleRouter,
            abi.encodeCall(
                IPendleRouter.redeemPyToToken, (
                    address(params.proxy),
                    yt,
                    params.pyAmountIn,
                    createSimpleTokenOutput(tokenOut, minTokenOut)
                )
            )
        );

        uint256 totalTokenOutAmount = IERC20(tokenOut).balanceOf(address(params.proxy)) - tokenOutAmountBefore;

        require(totalTokenOutAmount >= params.minAmountOut, "PendleLib/min-amount-not-met");

        params.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(params.rateLimitId, address(params.pendleMarket)),
            totalTokenOutAmount
        );

    }

}
