// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

interface IEETH is IERC20 {
    function liquidityPool() external view returns (address);
    function shares(address account) external view returns (uint256);
}

interface ILiquidityPool {
    function amountForShare(uint256 shareAmount) external view returns (uint256);
    function deposit() external;
    function requestWithdraw(address receiver,uint256 amount) external returns (uint256 requestId);
    function withdrawRequestNFT() external view returns (address);
}

interface IWEETHLike is IERC20 {
    function eETH() external view returns (address);
    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
    function wrap(uint256 amount) external returns (uint256);
}

interface IWeEthModule {
    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

library WeETHLib {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct DepositParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        uint256     amount;
        bytes32     rateLimitId;
    }

    struct WithdrawParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        uint256     weETHShares;
        bytes32     rateLimitId;
        address     weETHModule;
    }

    struct ClaimWithdrawalParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        uint256     requestId;
        address     weETHModule;
        bytes32     rateLimitId;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(DepositParams calldata params) external returns (uint256 shares) {
        _rateLimited(params.rateLimits, params.rateLimitId, params.amount);

        // Unwrap WETH to ETH
        params.proxy.doCall(
            Ethereum.WETH,
            abi.encodeCall(IWETH(Ethereum.WETH).withdraw, (params.amount))
        );

        // Deposit ETH to eETH
        address eETH          = IWEETHLike(Ethereum.WEETH).eETH();
        address liquidityPool = IEETH(eETH).liquidityPool();

        uint256 eETHShares = abi.decode(
            params.proxy.doCallWithValue(
                liquidityPool,
                abi.encodeCall(ILiquidityPool(liquidityPool).deposit, ()),
                params.amount
            ),
            (uint256)
        );
        uint256 eETHAmount = ILiquidityPool(liquidityPool).amountForShare(eETHShares);

        // Deposit eETH to weETH
        ApproveLib.approve(eETH, address(params.proxy), Ethereum.WEETH, eETHAmount);

        shares = abi.decode(
            params.proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(IWEETHLike(Ethereum.WEETH).wrap, (eETHAmount))
            ),
            (uint256)
        );
    }

    function requestWithdraw(
        WithdrawParams calldata params
    )
        external returns (uint256 requestId)
    {
        IWEETHLike weETH = IWEETHLike(Ethereum.WEETH);

        address eETH          = weETH.eETH();
        address liquidityPool = IEETH(eETH).liquidityPool();

        // Withdraw from weETH (returns eETH)
        uint256 eETHAmount = abi.decode(
            params.proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(
                    weETH.unwrap,
                    (params.weETHShares)
                )
            ),
            (uint256)
        );

        _rateLimited(params.rateLimits, params.rateLimitId, eETHAmount);

        // Request withdrawal of ETH from EETH
        ApproveLib.approve(eETH, address(params.proxy), liquidityPool, eETHAmount);

        requestId = abi.decode(
            params.proxy.doCall(
                liquidityPool,
                abi.encodeCall(
                    ILiquidityPool(liquidityPool).requestWithdraw,
                    (address(params.weETHModule), eETHAmount)
                )
            ),
            (uint256)
        );
    }

    function claimWithdrawal(
        ClaimWithdrawalParams calldata params
    )
        external returns (uint256 ethReceived)
    {
        ethReceived =  abi.decode(
            params.proxy.doCall(
                params.weETHModule,
                abi.encodeCall(IWeEthModule(params.weETHModule).claimWithdrawal, (params.requestId))
            ),
            (uint256)
        );

        _rateLimited(params.rateLimits, params.rateLimitId, ethReceived);
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
