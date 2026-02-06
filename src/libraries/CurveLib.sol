// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IERC20Like {

    function totalSupply() external view returns (uint256);

}

interface ICurvePoolLike is IERC20Like {

    function add_liquidity(uint256[] memory amounts, uint256 minMintAmount, address receiver)
        external;

    function balances(uint256 index) external view returns (uint256);

    function coins(uint256 index) external returns (address);

    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    )
        external
        returns (uint256 tokensOut);

    function get_virtual_price() external view returns (uint256);

    function N_COINS() external view returns (uint256);

    function remove_liquidity(
        uint256          burnAmount,
        uint256[] memory minAmounts,
        address          receiver
    )
        external;

    function stored_rates() external view returns (uint256[] memory);

}

library CurveLib {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant LIMIT_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swap(
        address proxy,
        address rateLimits,
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxSlippage
    )
        external
        returns (uint256 amountOut)
    {
        require(inputIndex != outputIndex, "CurveLib/invalid-indices");
        require(maxSlippage != 0,          "CurveLib/max-slippage-not-set");

        require(
            inputIndex < ICurvePoolLike(pool).N_COINS() &&
            outputIndex < ICurvePoolLike(pool).N_COINS(),
            "CurveLib/index-too-high"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        uint256 valueIn = _toNormalizedAmount(amountIn, rates[inputIndex]);

        // Below code is simplified from the following logic.
        // `maxSlippage` was multiplied first to avoid precision loss.
        //   valueIn   = amountIn * rates[inputIndex] / 1e18  // 18 decimal precision, USD
        //   tokensOut = valueIn * 1e18 / rates[outputIndex]  // Token precision, token amount
        //   result    = tokensOut * maxSlippage / 1e18
        require(
            minAmountOut >= valueIn * maxSlippage / rates[outputIndex],
            "CurveLib/min-amount-not-met"
        );

        _decreaseRateLimit(rateLimits, LIMIT_SWAP, pool, valueIn);

        ApproveLib.approve(
            ICurvePoolLike(pool).coins(inputIndex),
            proxy,
            pool,
            amountIn
        );

        bytes memory callData = abi.encodeCall(
            ICurvePoolLike.exchange,
            (
                int128(int256(inputIndex)),   // safe cast because of 8 token max
                int128(int256(outputIndex)),  // safe cast because of 8 token max
                amountIn,
                minAmountOut,
                proxy
            )
        );

        return abi.decode(IALMProxy(proxy).doCall(pool, callData), (uint256));
    }

    function addLiquidity(
        address            proxy,
        address            rateLimits,
        address            pool,
        uint256            minLpAmount,
        uint256            maxSlippage,
        uint256[] calldata depositAmounts
    )
        external
        returns (uint256 shares)
    {
        require(maxSlippage != 0, "CurveLib/max-slippage-not-set");

        require(
            depositAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveLib/invalid-deposit-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Aggregate the value of the deposited assets (e.g. USD).
        uint256 valueDeposited;
        for (uint256 i = 0; i < depositAmounts.length; ++i) {
            ApproveLib.approve(
                ICurvePoolLike(pool).coins(i),
                proxy,
                pool,
                depositAmounts[i]
            );

            valueDeposited += depositAmounts[i] * rates[i];
        }
        valueDeposited /= 1e18;

        // Ensure minimum LP amount expected is greater than max slippage amount.
        // Intentionally reverts when get_virtual_price() == 0 to prevent adding liquidity to
        // unseeded pools.
        require(
            minLpAmount >=
            valueDeposited * maxSlippage / ICurvePoolLike(pool).get_virtual_price(),
            "CurveLib/min-amount-not-met"
        );

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD).
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, pool, valueDeposited);

        shares = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(ICurvePoolLike.add_liquidity, (depositAmounts, minLpAmount, proxy))
            ),
            (uint256)
        );

        uint256 totalSupply = ICurvePoolLike(pool).totalSupply();

        // Compute the swap value by taking the difference of the current underlying
        // asset values from minted shares vs the deposited funds, converting this into an
        // aggregated swap "amount in" by dividing the total value moved by two and decrease the
        // swap rate limit by this amount.
        uint256 totalSwapped;
        for (uint256 i; i < depositAmounts.length; ++i) {
            totalSwapped += _absSubtraction(
                ICurvePoolLike(pool).balances(i) * rates[i] * shares / totalSupply,
                depositAmounts[i] * rates[i]
            );
        }
        totalSwapped /= 1e18;

        _decreaseRateLimit(rateLimits, LIMIT_SWAP, pool, totalSwapped / 2); // average swap
    }

    function removeLiquidity(
        address            proxy,
        address            rateLimits,
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts,
        uint256            maxSlippage
    )
        external
        returns (uint256[] memory withdrawnTokens)
    {
        require(maxSlippage != 0, "CurveLib/max-slippage-not-set");

        require(
            minWithdrawAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveLib/invalid-min-withdraw-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Aggregate the minimum values of the withdrawn assets (e.g. USD)
        uint256 valueMinWithdrawn;
        for (uint256 i = 0; i < minWithdrawAmounts.length; ++i) {
            valueMinWithdrawn += minWithdrawAmounts[i] * rates[i];
        }
        valueMinWithdrawn /= 1e18;

        // Check that the aggregated minimums are greater than the max slippage amount
        require(
            valueMinWithdrawn >=
            lpBurnAmount * ICurvePoolLike(pool).get_virtual_price() * maxSlippage / 1e36,
            "CurveLib/min-amount-not-met"
        );

        withdrawnTokens = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(
                    ICurvePoolLike.remove_liquidity,
                    (lpBurnAmount, minWithdrawAmounts, proxy)
                )
            ),
            (uint256[])
        );

        // Aggregate value withdrawn to reduce the rate limit
        uint256 valueWithdrawn;
        for (uint256 i = 0; i < withdrawnTokens.length; ++i) {
            valueWithdrawn += withdrawnTokens[i] * rates[i];
        }
        valueWithdrawn /= 1e18;

        _decreaseRateLimit(rateLimits, LIMIT_WITHDRAW, pool, valueWithdrawn);
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address rateLimits, bytes32 key, address pool, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, pool), amount);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _fromNormalizedAmount(uint256 value, uint256 rate) internal pure returns (uint256) {
        return value * 1e18 / rate;
    }

    function _toNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * rate / 1e18;
    }

}
