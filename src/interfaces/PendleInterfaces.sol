// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

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

struct TokenOutput {
    address tokenOut;
    uint256 minTokenOut;
    address tokenRedeemSy;
    address pendleSwap;
    SwapData swapData;
}
interface IPendleRouter {
    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);
}

interface IPendleMarket {
    function readTokens() external view returns (address _SY, address _PT, address _YT);
    function isExpired() external view returns (bool);
    function expiry() external view returns (uint256);
}

interface ISY {
    function yieldToken() external view returns (address);
    function exchangeRate() external view returns (uint256);
}
