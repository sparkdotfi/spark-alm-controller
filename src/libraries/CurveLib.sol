// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy } from "../interfaces/IALMProxy.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";
import { Types }            from "./Types.sol";

interface ICurvePoolLike is IERC20 {
    function add_liquidity(
        uint256[] memory amounts,
        uint256 minMintAmount,
        address receiver
    ) external;
    function balances(uint256 index) external view returns (uint256);
    function coins(uint256 index) external returns (address);
    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokensOut);
    function get_virtual_price() external view returns (uint256);
    function N_COINS() external view returns (uint256);
    function remove_liquidity(
        uint256 burnAmount,
        uint256[] memory minAmounts,
        address receiver
    ) external;
    function stored_rates() external view returns (uint256[] memory);
}

library CurveLib {

    function swapCurve(
        Types.SwapCurveParams calldata param,
        IALMProxy proxy,
        IRateLimits rateLimits
    )
        external returns (uint256 amountOut)
    {
        require(param.inputIndex != param.outputIndex, "MainnetController/invalid-indices");

        require(param.maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(param.pool);

        uint256 numCoins = curvePool.N_COINS();
        require(
            param.inputIndex < numCoins && param.outputIndex < numCoins,
            "MainnetController/index-too-high"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Below code is simplified from the following logic.
        // `maxSlippage` was multipled first to avoid precision loss.
        //   valueIn   = amountIn * rates[inputIndex] / 1e18  // 18 decimal precision, USD
        //   tokensOut = valueIn * 1e18 / rates[outputIndex]  // Token precision, token amount
        //   result    = tokensOut * maxSlippage / 1e18
        uint256 minimumMinAmountOut = param.amountIn
            * rates[param.inputIndex]
            * param.maxSlippage
            / rates[param.outputIndex]
            / 1e18;

        require(
            param.minAmountOut >= minimumMinAmountOut,
            "MainnetController/min-amount-not-met"
        );

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(param.rateLimitId, param.pool),
            param.amountIn * rates[param.inputIndex] / 1e18
        );

        _approve(curvePool.coins(param.inputIndex), param.pool, param.amountIn, proxy);

        amountOut = abi.decode(
            proxy.doCall(
                param.pool,
                abi.encodeCall(
                    curvePool.exchange,
                    (
                        int128(int256(param.inputIndex)),   // safe cast because of 8 token max
                        int128(int256(param.outputIndex)),  // safe cast because of 8 token max
                        param.amountIn,
                        param.minAmountOut,
                        address(proxy)
                    )
                )
            ),
            (uint256)
        );
    }

    function addLiquidityCurve(
        Types.AddLiquidityParams calldata param,
        IALMProxy proxy,
        IRateLimits rateLimits
    )
        external returns (uint256 shares)
    {
        require(param.maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(param.pool);

        require(
            param.depositAmounts.length == curvePool.N_COINS(),
            "MainnetController/invalid-deposit-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the value of the deposited assets (e.g. USD)
        uint256 valueDeposited;
        for (uint256 i = 0; i < param.depositAmounts.length; i++) {
            _approve(curvePool.coins(i), param.pool, param.depositAmounts[i], proxy);
            valueDeposited += param.depositAmounts[i] * rates[i];
        }
        valueDeposited /= 1e18;

        // Ensure minimum LP amount expected is greater than max slippage amount.
        require(
            param.minLpAmount >= valueDeposited * param.maxSlippage / curvePool.get_virtual_price(),
            "MainnetController/min-amount-not-met"
        );

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD)
        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(param.addLiquidityRateLimitId, param.pool),
            valueDeposited
        );

        shares = abi.decode(
            proxy.doCall(
                param.pool,
                abi.encodeCall(
                    curvePool.add_liquidity,
                    (param.depositAmounts, param.minLpAmount, address(proxy))
                )
            ),
            (uint256)
        );

        // Compute the swap value by taking the difference of the current underlying
        // asset values from minted shares vs the deposited funds, converting this into an
        // aggregated swap "amount in" by dividing the total value moved by two and decrease the
        // swap rate limit by this amount.
        uint256 totalSwapped;
        for (uint256 i; i < param.depositAmounts.length; i++) {
            totalSwapped += _absSubtraction(
                curvePool.balances(i) * rates[i] * shares / curvePool.totalSupply(),
                param.depositAmounts[i] * rates[i]
            );
        }
        uint256 averageSwap = totalSwapped / 2 / 1e18;

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(param.swapRateLimitId, param.pool),
            averageSwap
        );
    }

    function removeLiquidityCurve(
        address pool,
        uint256 lpBurnAmount,
        uint256[] memory minWithdrawAmounts,
        uint256 maxSlippage,
        IALMProxy proxy,
        IRateLimits rateLimits,
        bytes32 rateLimitId
    )
        external returns (uint256[] memory withdrawnTokens)
    {
        require(maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(pool);

        require(
            minWithdrawAmounts.length == curvePool.N_COINS(),
            "MainnetController/invalid-min-withdraw-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the minimum values of the withdrawn assets (e.g. USD)
        uint256 valueMinWithdrawn;
        for (uint256 i = 0; i < minWithdrawAmounts.length; i++) {
            valueMinWithdrawn += minWithdrawAmounts[i] * rates[i];
        }
        valueMinWithdrawn /= 1e18;

        // Check that the aggregated minimums are greater than the max slippage amount
        require(
            valueMinWithdrawn >= lpBurnAmount * curvePool.get_virtual_price() * maxSlippage / 1e36,
            "MainnetController/min-amount-not-met"
        );

        withdrawnTokens = abi.decode(
            proxy.doCall(
                pool,
                abi.encodeCall(
                    curvePool.remove_liquidity,
                    (lpBurnAmount, minWithdrawAmounts, address(proxy))
                )
            ),
            (uint256[])
        );

        // Aggregate value withdrawn to reduce the rate limit
        uint256 valueWithdrawn;
        for (uint256 i = 0; i < withdrawnTokens.length; i++) {
            valueWithdrawn += withdrawnTokens[i] * rates[i];
        }
        valueWithdrawn /= 1e18;

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(rateLimitId, pool),
            valueWithdrawn
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _approve(
        address token,
        address spender,
        uint256 amount,
        IALMProxy proxy
    )
        internal
    {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

}
