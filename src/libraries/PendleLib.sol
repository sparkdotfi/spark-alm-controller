// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

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

        uint256 exchangeRate  = ISY(sy).exchangeRate();
        uint256 pyIndexStored = IYT(yt).pyIndexStored();

        uint256 pyIndexCurrent = exchangeRate > pyIndexStored ? exchangeRate : pyIndexStored;

        // expected to receive full amount, but the buffer is subtracted
        // to avoid reverts due to potential rounding errors
        uint256 minTokenOut = params.pyAmountIn * 1e18 / pyIndexCurrent - 5;

        _approve(params.proxy, pt, params.pendleRouter, params.pyAmountIn);

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

    function _approve(
        IALMProxy proxy,
        address   token,
        address   spender,
        uint256   amount
    )
        internal
    {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token
        ( bool success, bytes memory data )
            = address(proxy).call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        bytes memory approveCallReturnData;

        if (success) {
            // Data is the ABI-encoding of the approve call bytes return data, need to
            // decode it first
            approveCallReturnData = abi.decode(data, (bytes));
            // Approve was successful if 1) no return value or 2) true return value
            if (approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool))) {
                return;
            }
        }

        // If call was unsuccessful, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));

        approveCallReturnData = proxy.doCall(token, approveData);

        // Revert if approve returns false
        require(
            approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool)),
            "PendleLib/approve-failed"
        );
    }

}
