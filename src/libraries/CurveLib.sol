// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy } from "../interfaces/IALMProxy.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

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

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct SwapCurveParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     pool;
        bytes32     rateLimitId;
        uint256     inputIndex;
        uint256     outputIndex;
        uint256     amountIn;
        uint256     minAmountOut;
        uint256     maxSlippage;
    }

    struct AddLiquidityParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     pool;
        bytes32     addLiquidityRateLimitId;
        bytes32     swapRateLimitId;
        uint256     minLpAmount;
        uint256     maxSlippage;
        uint256[]   depositAmounts;
    }

    struct RemoveLiquidityParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     pool;
        bytes32     rateLimitId;
        uint256     lpBurnAmount;
        uint256[]   minWithdrawAmounts;
        uint256     maxSlippage;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swap(SwapCurveParams calldata params) external returns (uint256 amountOut) {
        require(params.inputIndex != params.outputIndex, "MainnetController/invalid-indices");

        require(params.maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(params.pool);

        uint256 numCoins = curvePool.N_COINS();
        require(
            params.inputIndex < numCoins && params.outputIndex < numCoins,
            "MainnetController/index-too-high"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Below code is simplified from the following logic.
        // `maxSlippage` was multipled first to avoid precision loss.
        //   valueIn   = amountIn * rates[inputIndex] / 1e18  // 18 decimal precision, USD
        //   tokensOut = valueIn * 1e18 / rates[outputIndex]  // Token precision, token amount
        //   result    = tokensOut * maxSlippage / 1e18
        uint256 minimumMinAmountOut = params.amountIn
            * rates[params.inputIndex]
            * params.maxSlippage
            / rates[params.outputIndex]
            / 1e18;

        require(
            params.minAmountOut >= minimumMinAmountOut,
            "MainnetController/min-amount-not-met"
        );

        params.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(params.rateLimitId, params.pool),
            params.amountIn * rates[params.inputIndex] / 1e18
        );

        _approve(
            params.proxy,
            curvePool.coins(params.inputIndex),
            params.pool,
            params.amountIn
        );

        amountOut = abi.decode(
            params.proxy.doCall(
                params.pool,
                abi.encodeCall(
                    curvePool.exchange,
                    (
                        int128(int256(params.inputIndex)),   // safe cast because of 8 token max
                        int128(int256(params.outputIndex)),  // safe cast because of 8 token max
                        params.amountIn,
                        params.minAmountOut,
                        address(params.proxy)
                    )
                )
            ),
            (uint256)
        );
    }

    function addLiquidity(AddLiquidityParams calldata params) external returns (uint256 shares) {
        require(params.maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(params.pool);

        require(
            params.depositAmounts.length == curvePool.N_COINS(),
            "MainnetController/invalid-deposit-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the value of the deposited assets (e.g. USD)
        uint256 valueDeposited;
        for (uint256 i = 0; i < params.depositAmounts.length; i++) {
            _approve(
                params.proxy,
                curvePool.coins(i),
                params.pool,
                params.depositAmounts[i]
            );
            valueDeposited += params.depositAmounts[i] * rates[i];
        }
        valueDeposited /= 1e18;

        // Ensure minimum LP amount expected is greater than max slippage amount.
        require(
            params.minLpAmount >= valueDeposited
                * params.maxSlippage
                / curvePool.get_virtual_price(),
            "MainnetController/min-amount-not-met"
        );

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD)
        params.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(params.addLiquidityRateLimitId, params.pool),
            valueDeposited
        );

        shares = abi.decode(
            params.proxy.doCall(
                params.pool,
                abi.encodeCall(
                    curvePool.add_liquidity,
                    (params.depositAmounts, params.minLpAmount, address(params.proxy))
                )
            ),
            (uint256)
        );

        // Compute the swap value by taking the difference of the current underlying
        // asset values from minted shares vs the deposited funds, converting this into an
        // aggregated swap "amount in" by dividing the total value moved by two and decrease the
        // swap rate limit by this amount.
        uint256 totalSwapped;
        for (uint256 i; i < params.depositAmounts.length; i++) {
            totalSwapped += _absSubtraction(
                curvePool.balances(i) * rates[i] * shares / curvePool.totalSupply(),
                params.depositAmounts[i] * rates[i]
            );
        }
        uint256 averageSwap = totalSwapped / 2 / 1e18;

        params.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(params.swapRateLimitId, params.pool),
            averageSwap
        );
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (uint256[] memory withdrawnTokens)
    {
        require(params.maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(params.pool);

        require(
            params.minWithdrawAmounts.length == curvePool.N_COINS(),
            "MainnetController/invalid-min-withdraw-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the minimum values of the withdrawn assets (e.g. USD)
        uint256 valueMinWithdrawn;
        for (uint256 i = 0; i < params.minWithdrawAmounts.length; i++) {
            valueMinWithdrawn += params.minWithdrawAmounts[i] * rates[i];
        }
        valueMinWithdrawn /= 1e18;

        // Check that the aggregated minimums are greater than the max slippage amount
        require(
            valueMinWithdrawn >= params.lpBurnAmount
                * curvePool.get_virtual_price()
                * params.maxSlippage
                / 1e36,
            "MainnetController/min-amount-not-met"
        );

        withdrawnTokens = abi.decode(
            params.proxy.doCall(
                params.pool,
                abi.encodeCall(
                    curvePool.remove_liquidity,
                    (params.lpBurnAmount, params.minWithdrawAmounts, address(params.proxy))
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

        params.rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(params.rateLimitId, params.pool),
            valueWithdrawn
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

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

        // Decode the first 32 bytes of the data, ALMProxy returns 96 bytes
        bytes32 result;
        assembly { result := mload(add(data, 32)) }

        // Decode the result to check if the approval was successful
        bool decodedSuccess = (data.length == 0) || result != bytes32(0);

        // If call succeeded with expected calldata, return
        if (success && decodedSuccess) return;

        // If call reverted, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

}
