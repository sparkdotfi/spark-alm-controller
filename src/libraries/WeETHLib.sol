// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

interface IEETHLike is IERC20 {
    function liquidityPool() external view returns (address);
    function shares(address account) external view returns (uint256);
}

interface ILiquidityPoolLike {
    function amountForShare(uint256 shareAmount) external view returns (uint256);
    function deposit() external;
    function requestWithdraw(address receiver,uint256 amount) external returns (uint256 requestId);
    function sharesForAmount(uint256 amount) external view returns (uint256);
    function withdrawRequestNFT() external view returns (address);
}

interface IWEETHLike is IERC20 {
    function eETH() external view returns (address);
    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256);
    function unwrap(uint256 amount) external returns (uint256);
    function wrap(uint256 amount) external returns (uint256);
}

interface IWeEthModuleLike {
    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);
}

interface IWETHLike {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

library WeETHLib {

    bytes32 public constant LIMIT_WEETH_CLAIM_WITHDRAW   = keccak256("LIMIT_WEETH_CLAIM_WITHDRAW");
    bytes32 public constant LIMIT_WEETH_DEPOSIT          = keccak256("LIMIT_WEETH_DEPOSIT");
    bytes32 public constant LIMIT_WEETH_REQUEST_WITHDRAW = keccak256("LIMIT_WEETH_REQUEST_WITHDRAW");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(
        IALMProxy   proxy,
        IRateLimits rateLimits,
        uint256     amount,
        uint256     minSharesOut
    ) external returns (uint256 shares) {
        _rateLimited(rateLimits, LIMIT_WEETH_DEPOSIT, amount);

        // Unwrap WETH to ETH.
        proxy.doCall(
            Ethereum.WETH,
            abi.encodeCall(IWETHLike(Ethereum.WETH).withdraw, (amount))
        );

        // Deposit ETH to eETH.
        address eETH          = IWEETHLike(Ethereum.WEETH).eETH();
        address liquidityPool = IEETHLike(eETH).liquidityPool();

        uint256 eETHShares = abi.decode(
            proxy.doCallWithValue(
                liquidityPool,
                abi.encodeCall(ILiquidityPoolLike(liquidityPool).deposit, ()),
                amount
            ),
            (uint256)
        );

        uint256 eETHAmount = ILiquidityPoolLike(liquidityPool).amountForShare(eETHShares);

        // Deposit eETH to weETH.
        ApproveLib.approve(eETH, address(proxy), Ethereum.WEETH, eETHAmount);

        shares = abi.decode(
            proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(IWEETHLike(Ethereum.WEETH).wrap, (eETHAmount))
            ),
            (uint256)
        );

        require(shares >= minSharesOut, "MC/slippage-too-high");
    }

    function requestWithdraw(
        IALMProxy   proxy,
        IRateLimits rateLimits,
        uint256     weETHShares,
        address     weETHModule
    )
        external returns (uint256 requestId)
    {
        IWEETHLike weETH = IWEETHLike(Ethereum.WEETH);

        address eETH          = weETH.eETH();
        address liquidityPool = IEETHLike(eETH).liquidityPool();

        // Withdraw from weETH (returns eETH).
        uint256 eETHAmount = abi.decode(
            proxy.doCall(
                Ethereum.WEETH,
                abi.encodeCall(
                    weETH.unwrap,
                    (weETHShares)
                )
            ),
            (uint256)
        );

        // NOTE: weETHModule is enforced to be correct by the rate limit key
        _rateLimited(
            rateLimits,
            RateLimitHelpers.makeAddressKey(LIMIT_WEETH_REQUEST_WITHDRAW, weETHModule),
            eETHAmount
        );

        // Request withdrawal of ETH from EETH.
        ApproveLib.approve(eETH, address(proxy), liquidityPool, eETHAmount);

        requestId = abi.decode(
            proxy.doCall(
                liquidityPool,
                abi.encodeCall(
                    ILiquidityPoolLike(liquidityPool).requestWithdraw,
                    (weETHModule, eETHAmount)
                )
            ),
            (uint256)
        );
    }

    function claimWithdrawal(
        IALMProxy   proxy,
        IRateLimits rateLimits,
        uint256     requestId,
        address     weETHModule
    )
        external returns (uint256 ethReceived)
    {
        ethReceived =  abi.decode(
            proxy.doCall(
                weETHModule,
                abi.encodeCall(IWeEthModuleLike(weETHModule).claimWithdrawal, (requestId))
            ),
            (uint256)
        );

        // NOTE: weETHModule is enforced to be correct by the rate limit key
        _rateLimited(
            rateLimits,
            RateLimitHelpers.makeAddressKey(LIMIT_WEETH_CLAIM_WITHDRAW, weETHModule),
            ethReceived
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
