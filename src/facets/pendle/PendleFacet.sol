// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IPendleFacet } from "./IPendleFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

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

contract PendleFacet is IPendleFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_REDEEM = keccak256("LIMIT_PENDLE_PT_REDEEM");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override router;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address router_) {
        router = router_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    // NOTE: DO NOT use for markets with non-standard SYs, without additional testing
    //       targeting each onboarded non-standard SY market.
    //       (Non-standard SYs: ePENDLE, mPENDLE, aTokens (aUSDC, aUSDT))
    function redeem(address market, uint256 pyAmountIn, uint256 minAmountOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        require(IPendleMarketLike(market).isExpired(), "PendleFacet/market-not-expired");
        require(minAmountOut != 0,                     "PendleFacet/min-amount-out-not-set");

        uint256 totalTokenOutAmount = _executePyRedeem(market, pyAmountIn);

        require(totalTokenOutAmount >= minAmountOut, "PendleFacet/min-amount-not-met");

        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REDEEM, market),
            totalTokenOutAmount
        );

        emit PendleRedeem(market, pyAmountIn, totalTokenOutAmount);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _executePyRedeem(address market, uint256 pyAmountIn)
        internal
        returns (uint256 totalTokenOutAmount)
    {
        ( address sy, address pt, address yt ) = IPendleMarketLike(market).readTokens();

        address tokenOut = ISYLike(sy).yieldToken();

        // Expecting to receive full amount, but the buffer is subtracted to avoid reverts due to
        // potential rounding errors.
        uint256 minTokenOut = pyAmountIn * 1e18 / IYTLike(yt).pyIndexCurrent() - 5;
        address proxy       = _getSharedControllerStorage().proxy;

        ApproveLib.approve(pt, proxy, router, pyAmountIn);

        uint256 tokenOutAmountBefore = IERC20Like(tokenOut).balanceOf(proxy);

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

        totalTokenOutAmount = IERC20Like(tokenOut).balanceOf(proxy) - tokenOutAmountBefore;
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

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
