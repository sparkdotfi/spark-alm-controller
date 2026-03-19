// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

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
        mapping (address => uint256) storage maxSlippages
    )
        external
        returns (uint256 amountOut)
    {
        require(inputIndex != outputIndex, "CurveLib/invalid-indices");
        require(maxSlippages[pool] != 0,   "CurveLib/max-slippage-not-set");

        uint256 numCoins = ICurvePoolLike(pool).N_COINS();

        require(inputIndex < numCoins && outputIndex < numCoins,"CurveLib/index-too-high");

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Makes the assumption that value in should equal value out.
        uint256 valueIn             = _toNormalizedAmount(amountIn,  rates[inputIndex]);
        uint256 equivalentAmountOut = _fromNormalizedAmount(valueIn, rates[outputIndex]);

        require(
            minAmountOut >= equivalentAmountOut * maxSlippages[pool] / 1e18,
            "CurveLib/min-amount-not-met"
        );

        _decreaseRateLimit(rateLimits, LIMIT_SWAP, pool, valueIn);

        ApproveLib.approve(
            ICurvePoolLike(pool).coins(inputIndex),
            proxy,
            pool,
            amountIn
        );

        bytes memory callData = _getExchangeCalldata(proxy, inputIndex, outputIndex, amountIn, minAmountOut);

        return abi.decode(IALMProxy(proxy).doCall(pool, callData), (uint256));
    }

    function addLiquidity(
        address            proxy,
        address            rateLimits,
        address            pool,
        uint256            minLpAmount,
        uint256[] calldata depositAmounts,
        mapping (address => uint256) storage maxSlippages
    )
        external
        returns (uint256 shares)
    {
        require(maxSlippages[pool] != 0, "CurveLib/max-slippage-not-set");

        require(
            depositAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveLib/invalid-deposit-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
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
            valueDeposited * maxSlippages[pool] / ICurvePoolLike(pool).get_virtual_price(),
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

        // Compute the swap value by taking the difference of the current underlying asset values
        // from minted shares vs the deposited funds.
        uint256 totalSwapped;
        for (uint256 i; i < depositAmounts.length; ++i) {
            totalSwapped += _absSubtraction(
                ICurvePoolLike(pool).balances(i) * rates[i] * shares / totalSupply,
                depositAmounts[i] * rates[i]
            );
        }
        totalSwapped /= 1e18;

        // Convert the total value moved into an aggregated swap "amount in" by dividing it by 2.
        _decreaseRateLimit(rateLimits, LIMIT_SWAP, pool, totalSwapped / 2);
    }

    function removeLiquidity(
        address            proxy,
        address            rateLimits,
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts,
        mapping (address => uint256) storage maxSlippages
    )
        external
        returns (uint256[] memory withdrawnTokens)
    {
        require(maxSlippages[pool] != 0, "CurveLib/max-slippage-not-set");

        require(
            minWithdrawAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveLib/invalid-min-withdraw-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Aggregate the minimum values of the withdrawn assets (e.g. USD).
        uint256 valueMinWithdrawn;
        for (uint256 i = 0; i < minWithdrawAmounts.length; ++i) {
            valueMinWithdrawn += minWithdrawAmounts[i] * rates[i];
        }
        valueMinWithdrawn /= 1e18;

        // Check that the aggregated minimums are greater than the max slippage amount.
        require(
            valueMinWithdrawn >=
            lpBurnAmount * ICurvePoolLike(pool).get_virtual_price() * maxSlippages[pool] / 1e36,
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

        // Aggregate value withdrawn to reduce the rate limit.
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

    function _getExchangeCalldata(
        address proxy,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(
            ICurvePoolLike.exchange,
            (
                int128(int256(inputIndex)),   // Safe cast because of 8 token max.
                int128(int256(outputIndex)),  // Safe cast because of 8 token max.
                amountIn,
                minAmountOut,
                proxy
            )
        );
    }

    function _fromNormalizedAmount(uint256 value, uint256 rate) internal pure returns (uint256) {
        return value * 1e18 / rate;
    }

    function _toNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * rate / 1e18;
    }

}
