// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IWEETHFacet } from "./IWEETHFacet.sol";

interface IEETHLike {

    function liquidityPool() external view returns (address);

}

interface ILiquidityPoolLike {

    function amountForShare(uint256 shareAmount) external view returns (uint256);

    function sharesForAmount(uint256 amount) external view returns (uint256);

    function deposit() external payable returns (uint256 shareAmount);

    function requestWithdraw(address receiver, uint256 amount) external returns (uint256 requestId);

}

interface IWEETHLike {

    function eETH() external view returns (address);

    function unwrap(uint256 amount) external returns (uint256);

    function wrap(uint256 amount) external returns (uint256);

}

interface IWEETHModuleLike {

    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);

}

interface IWETHLike {

    function withdraw(uint256 amount) external;

}

contract WEETHFacet is IWEETHFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_DEPOSIT          = keccak256("LIMIT_WEETH_DEPOSIT");
    bytes32 public constant override LIMIT_REQUEST_WITHDRAW = keccak256("LIMIT_WEETH_REQUEST_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override weth;
    address public immutable override weeth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_, address weeth_) {
        require(weth_  != address(0), "WEETHFacet/zero-weth");
        require(weeth_ != address(0), "WEETHFacet/zero-weeth");

        weth  = weth_;
        weeth = weeth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function deposit(uint256 amount, uint256 minSharesOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_DEPOSIT, amount);

        address proxy = $.proxy;

        // Unwrap WETH to ETH.
        IALMProxy(proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        // Deposit ETH to eETH.
        address eeth          = IWEETHLike(weeth).eETH();
        address liquidityPool = IEETHLike(eeth).liquidityPool();

        uint256 eethShares = abi.decode(
            IALMProxy(proxy).doCallWithValue(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike.deposit, ()),
                amount
            ),
            (uint256)
        );

        uint256 eethAmount = ILiquidityPoolLike(liquidityPool).amountForShare(eethShares);

        // Deposit eETH to weETH.
        ApproveLib.approve(eeth, proxy, weeth, eethAmount);

        shares = abi.decode(
            IALMProxy(proxy).doCall(weeth, abi.encodeCall(IWEETHLike.wrap, (eethAmount))),
            (uint256)
        );

        require(shares >= minSharesOut, "WEETHFacet/slippage-too-high");

        emit WEETHDeposit(amount, eethAmount, shares);
    }

    function requestWithdraw(address weethModule, uint256 weethShares, uint256 minEETHShares)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 requestId)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy         = $.proxy;
        address eeth          = IWEETHLike(weeth).eETH();
        address liquidityPool = IEETHLike(eeth).liquidityPool();

        // Withdraw from weETH (returns eETH).
        uint256 eethAmount = abi.decode(
            IALMProxy(proxy).doCall(
                weeth,
                abi.encodeCall(IWEETHLike.unwrap, (weethShares))
            ),
            (uint256)
        );

        // Protect against cumulative rate slippage across both conversions.
        require(
            ILiquidityPoolLike(liquidityPool).sharesForAmount(eethAmount) >= minEETHShares,
            "WEETHFacet/slippage-too-high"
        );

        // NOTE: An authorized weethModule is enforced by the rate limit key.
        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REQUEST_WITHDRAW, weethModule),
            eethAmount
        );

        // Request withdrawal of ETH from eETH.
        ApproveLib.approve(eeth, proxy, liquidityPool, eethAmount);

        requestId = abi.decode(
            IALMProxy(proxy).doCall(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike.requestWithdraw, (weethModule, eethAmount))
            ),
            (uint256)
        );

        emit WEETHRequestWithdraw(weethModule, requestId, eethAmount, weethShares);
    }

    function claimWithdrawal(address weethModule, uint256 requestId)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 wethReceived)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        // NOTE: An authorized weethModule is enforced by the rate limit key.
        require(
            IRateLimits($.rateLimits).getRateLimitData(
                makeAddressKey(LIMIT_REQUEST_WITHDRAW, weethModule)
            ).maxAmount > 0,
            "WEETHFacet/invalid-action"
        );

        wethReceived = abi.decode(
            IALMProxy($.proxy).doCall(
                weethModule,
                abi.encodeCall(IWEETHModuleLike.claimWithdrawal, (requestId))
            ),
            (uint256)
        );

        emit WEETHClaimWithdrawal(weethModule, requestId, wethReceived);
    }

}
