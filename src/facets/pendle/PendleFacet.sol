// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

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

contract PendleFacet is IPendleFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_REDEEM = keccak256("LIMIT_PENDLE_PT_REDEEM");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IPendleFacet
    address public immutable override router;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address router_) {
        require(router_ != address(0), "PendleFacet/zero-router");

        router = router_;
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    // NOTE: DO NOT use for markets with non-standard SYs, without additional testing
    //       targeting each onboarded non-standard SY market.
    //       (Non-standard SYs: ePENDLE, mPENDLE, aTokens (aUSDC, aUSDT))
    /// @inheritdoc IPendleFacet
    function redeem(address market, uint256 pyAmountIn, uint256 minAmountOut)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(IPendleMarketLike(market).isExpired(), "PendleFacet/market-not-expired");
        require(minAmountOut != 0,                     "PendleFacet/min-amount-out-not-set");

        ( address sy, address pt, address yt ) = IPendleMarketLike(market).readTokens();

        address tokenOut = ISYLike(sy).yieldToken();

        // Expecting to receive full amount, but the buffer is subtracted to avoid reverts due to
        // potential rounding errors.
        uint256 minTokenOut = pyAmountIn * 1e18 / IYTLike(yt).pyIndexCurrent() - 5;

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(pt, proxy, router, pyAmountIn);

        uint256 startingTokenOutAmount = IERC20Like(tokenOut).balanceOf(proxy);

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

        uint256 tokenOutAmount = IERC20Like(tokenOut).balanceOf(proxy) - startingTokenOutAmount;

        require(tokenOutAmount >= minAmountOut, "PendleFacet/min-amount-not-met");

        _decreaseRateLimit(getRedeemRateLimitKey(market, pt), tokenOutAmount);

        // Clear approvals
        ApproveLib.approve(pt, proxy, router, 0);

        emit PendleRedeem(market, pyAmountIn, tokenOutAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IPendleFacet
    function getRedeemRateLimitKey(address market, address pt)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_REDEEM, pt, market);
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
