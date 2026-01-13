// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { IRateLimits }  from "../interfaces/IRateLimits.sol";
import { IALMProxy }    from "../interfaces/IALMProxy.sol";

interface IEETH {
    function liquidityPool() external view returns (address);
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
        uint256     amount;
        bytes32     rateLimitId;
        address     weEthModule;
    }

    struct ClaimWithdrawalParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        uint256     requestId;
        address     weEthModule;
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

        // Deposit ETH to EETH
        address eETH = IWEETHLike(Ethereum.WEETH).eETH();
        address liquidityPool = IEETH(eETH).liquidityPool();

        uint256 eEthReceived = abi.decode(
            params.proxy.doCallWithValue(
                liquidityPool,
                abi.encodeCall(ILiquidityPool(liquidityPool).deposit, ()),
                params.amount
            ),
            (uint256)
        );

        // Deposit EETH to weETH
        ApproveLib.approve(eETH, address(params.proxy), Ethereum.WEETH, eEthReceived);

        shares = abi.decode(
            params.proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(IWEETHLike(Ethereum.WEETH).wrap, (eEthReceived))
            ),
            (uint256)
        );
    }

    function requestWithdraw(WithdrawParams calldata params) external returns (uint256 requestId) {
        IWEETHLike weETH = IWEETHLike(Ethereum.WEETH);

        _rateLimited(
            params.rateLimits,
            params.rateLimitId,
            weETH.getEETHByWeETH(params.amount)
        );

        // Withdraw from weETH (returns eETH)
        uint256 eEthWithdrawn = abi.decode(
            params.proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(
                    weETH.unwrap,
                    (params.amount)
                )
            ),
            (uint256)
        );

        // Request withdrawal of ETH from EETH
        address eETH          = weETH.eETH();
        address liquidityPool = IEETH(eETH).liquidityPool();

        ApproveLib.approve(eETH, address(params.proxy), liquidityPool, eEthWithdrawn);

        requestId = abi.decode(
            params.proxy.doCall(
                liquidityPool,
                abi.encodeCall(
                    ILiquidityPool(liquidityPool).requestWithdraw,
                    (address(params.weEthModule), eEthWithdrawn)
                )
            ),
            (uint256)
        );
    }

    function claimWithdrawal(ClaimWithdrawalParams calldata params) external returns (uint256 ethReceived) {
        _rateLimited(params.rateLimits, params.rateLimitId, params.requestId);

        return abi.decode(
            params.proxy.doCall(
                params.weEthModule,
                abi.encodeCall(IWeEthModule(params.weEthModule).claimWithdrawal, (params.requestId))
            ),
            (uint256)
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

    function _cancelRateLimit(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitIncrease(key, amount);
    }

}
