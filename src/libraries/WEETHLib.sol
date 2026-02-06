// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IEETHLike {

    function liquidityPool() external view returns (address);

}

interface ILiquidityPoolLike {

    function amountForShare(uint256 shareAmount) external view returns (uint256);

    function deposit() external payable returns (uint256 shareAmount);

    function requestWithdraw(address receiver,uint256 amount) external returns (uint256 requestId);

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

// NOTE: This library is is specifically for Mainnet Ethereum.
library WEETHLib {

    bytes32 public constant LIMIT_CLAIM_WITHDRAW   = keccak256("LIMIT_WEETH_CLAIM_WITHDRAW");
    bytes32 public constant LIMIT_DEPOSIT          = keccak256("LIMIT_WEETH_DEPOSIT");
    bytes32 public constant LIMIT_REQUEST_WITHDRAW = keccak256("LIMIT_WEETH_REQUEST_WITHDRAW");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(address proxy, address rateLimits, uint256 amount, uint256 minSharesOut)
        internal
        returns (uint256 shares)
    {
        _decreaseDepositRateLimit(rateLimits, amount);

        // Unwrap WETH to ETH.
        IALMProxy(proxy).doCall(Ethereum.WETH, abi.encodeCall(IWETHLike.withdraw, (amount)));

        // Deposit ETH to eETH.
        address eeth          = IWEETHLike(Ethereum.WEETH).eETH();
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
        ApproveLib.approve(eeth, proxy, Ethereum.WEETH, eethAmount);

        shares = abi.decode(
            IALMProxy(proxy).doCall(Ethereum.WEETH, abi.encodeCall(IWEETHLike.wrap, (eethAmount))),
            (uint256)
        );

        require(shares >= minSharesOut, "WEETHLib/slippage-too-high");
    }

    function requestWithdraw(
        address proxy,
        address rateLimits,
        uint256 weethShares,
        address weethModule
    )
        external
        returns (uint256 requestId)
    {
        address eeth          = IWEETHLike(Ethereum.WEETH).eETH();
        address liquidityPool = IEETHLike(eeth).liquidityPool();

        // Withdraw from weETH (returns eETH).
        uint256 eethAmount = abi.decode(
            IALMProxy(proxy).doCall(
                Ethereum.WEETH,
                abi.encodeCall(IWEETHLike.unwrap, (weethShares))
            ),
            (uint256)
        );

        // NOTE: An authorized weethModule is enforced by the rate limit key.
        _decreaseWEETHModuleRateLimit(rateLimits, LIMIT_REQUEST_WITHDRAW, weethModule, eethAmount);

        // Request withdrawal of ETH from eETH.
        ApproveLib.approve(eeth, proxy, liquidityPool, eethAmount);

        return abi.decode(
            IALMProxy(proxy).doCall(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike.requestWithdraw, (weethModule, eethAmount))
            ),
            (uint256)
        );
    }

    function claimWithdrawal(
        address proxy,
        address rateLimits,
        uint256 requestId,
        address weethModule
    )
        external
        returns (uint256 ethReceived)
    {
        ethReceived = abi.decode(
            IALMProxy(proxy).doCall(
                weethModule,
                abi.encodeCall(IWEETHModuleLike.claimWithdrawal, (requestId))
            ),
            (uint256)
        );

        // NOTE: An authorized weethModule is enforced by the rate limit key.
        _decreaseWEETHModuleRateLimit(rateLimits, LIMIT_CLAIM_WITHDRAW, weethModule, ethReceived);
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _decreaseDepositRateLimit(address rateLimits, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_DEPOSIT, amount);
    }

    function _decreaseWEETHModuleRateLimit(
        address rateLimits,
        bytes32 key,
        address weethModule,
        uint256 amount
    )
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, weethModule), amount);
    }

}
