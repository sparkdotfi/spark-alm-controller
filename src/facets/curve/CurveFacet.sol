// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { ICurveFacet } from "./ICurveFacet.sol";

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

contract CurveFacet is ICurveFacet, FacetBase {

    /**********************************************************************************************/
    /*** CurveFacet Storage Domain                                                              ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CurveFacet
    struct FacetStorage {
        mapping(address pool => uint256 maxSlippage) maxSlippages;  // 1e18 precision
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CurveFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x9bdc08d6fd054b5f8e5cf1735222ac93f34c8b6269da6b61f2bf1558f810b000;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant LIMIT_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "CurveFacet/pool-zero-address");

        emit CurveMaxSlippageSet(pool, _getFacetStorage().maxSlippages[pool] = maxSlippage);
    }

    function swap(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 amountOut)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(inputIndex  != outputIndex, "CurveFacet/invalid-indices");
        require(maxSlippage != 0,           "CurveFacet/max-slippage-not-set");

        uint256 numCoins = ICurvePoolLike(pool).N_COINS();

        require(inputIndex < numCoins && outputIndex < numCoins,"CurveFacet/index-too-high");

        (
            uint256 valueIn,
            uint256 equivalentAmountOut
        ) = _getSwapNormalizedValues(pool, inputIndex, outputIndex, amountIn);

        require(
            minAmountOut >= equivalentAmountOut * maxSlippage / 1e18,
            "CurveFacet/min-amount-not-met"
        );

        _decreaseRateLimit($.rateLimits, LIMIT_SWAP, pool, valueIn);

        ApproveLib.approve(
            ICurvePoolLike(pool).coins(inputIndex),
            $.proxy,
            pool,
            amountIn
        );

        bytes memory callData = _getExchangeCalldata($.proxy, inputIndex, outputIndex, amountIn, minAmountOut);

        return abi.decode(IALMProxy($.proxy).doCall(pool, callData), (uint256));
    }

    function addLiquidity(
        address            pool,
        uint256[] calldata depositAmounts,
        uint256            minLpAmount
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        require(
            depositAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveFacet/invalid-deposit-amounts"
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
            valueDeposited * maxSlippage / ICurvePoolLike(pool).get_virtual_price(),
            "CurveFacet/min-amount-not-met"
        );

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD).
        _decreaseRateLimit($.rateLimits, LIMIT_DEPOSIT, pool, valueDeposited);

        shares = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(ICurvePoolLike.add_liquidity, (depositAmounts, minLpAmount, proxy))
            ),
            (uint256)
        );

        _applySwapRateLimit(
            pool,
            depositAmounts,
            rates,
            $.rateLimits,
            shares
        );
    }

    function removeLiquidity(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256[] memory withdrawnTokens)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy = $.proxy;

        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        require(
            minWithdrawAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveFacet/invalid-min-withdraw-amounts"
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
            lpBurnAmount * ICurvePoolLike(pool).get_virtual_price() * maxSlippage / 1e36,
            "CurveFacet/min-amount-not-met"
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

        _decreaseRateLimit($.rateLimits, LIMIT_WITHDRAW, pool, valueWithdrawn);
    }

    /**********************************************************************************************/
    /*** View functions                                                                         ***/
    /**********************************************************************************************/

    function getMaxSlippage(address pool) external view returns (uint256) {
        return _getFacetStorage().maxSlippages[pool];
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

    function _getSwapNormalizedValues(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn
    ) internal view returns (uint256 valueIn, uint256 equivalentAmountOut) {
        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Makes the assumption that value in should equal value out.
        valueIn             = _toNormalizedAmount(amountIn,  rates[inputIndex]);
        equivalentAmountOut = _fromNormalizedAmount(valueIn, rates[outputIndex]);
    }

    function _applySwapRateLimit(
        address            pool,
        uint256[] calldata depositAmounts,
        uint256[] memory   rates,
        address            rateLimits,
        uint256            shares
    ) internal returns (uint256 totalSwapped) {
        uint256 totalSupply = ICurvePoolLike(pool).totalSupply();

        // Compute the swap value by taking the difference of the current underlying asset values
        // from minted shares vs the deposited funds.
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
