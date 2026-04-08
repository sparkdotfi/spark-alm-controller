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

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
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
        uint256            burnAmount,
        uint256[] calldata minAmounts,
        address            receiver
    )
        external;

    function stored_rates() external view returns (uint256[] memory);

}

contract CurveFacet is ICurveFacet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CurveFacet.v1
    struct FacetStorage {
        mapping (address pool => uint256 maxSlippage) maxSlippages;  // 1e18 precision
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CurveFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x13d34bc33acbcda590d5fdaf219fc6bf98cf53cf6ca8f2f488b9345e76156400;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant override LIMIT_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "CurveFacet/pool-zero-address");

        emit CurveMaxSlippageSet(pool, _getFacetStorage().maxSlippages[pool] = maxSlippage);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function swap(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 amountOut)
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(inputIndex  != outputIndex, "CurveFacet/invalid-indices");
        require(maxSlippage != 0,           "CurveFacet/max-slippage-not-set");

        uint256 numCoins = ICurvePoolLike(pool).N_COINS();

        require(inputIndex < numCoins && outputIndex < numCoins, "CurveFacet/index-too-high");

        (
            uint256 valueIn,
            uint256 equivalentAmountOut
        ) = _getSwapNormalizedValues(pool, inputIndex, outputIndex, amountIn);

        require(
            minAmountOut >= equivalentAmountOut * maxSlippage / 1e18,
            "CurveFacet/min-amount-not-met"
        );

        _decreaseRateLimit(LIMIT_SWAP, pool, valueIn);

        _approve(ICurvePoolLike(pool).coins(inputIndex), pool, amountIn);

        bytes memory callData = _getExchangeCalldata({
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut
        });

        amountOut = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(pool, callData),
            (uint256)
        );

        emit CurveSwap(pool, inputIndex, outputIndex, amountIn, amountOut);
    }

    function addLiquidity(address pool, uint256[] calldata depositAmounts, uint256 minLpAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
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
            _approve(ICurvePoolLike(pool).coins(i), pool, depositAmounts[i]);

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
        _decreaseRateLimit(LIMIT_DEPOSIT, pool, valueDeposited);

        address proxy = _getSharedControllerStorage().proxy;

        shares = abi.decode(
            IALMProxy(proxy).doCall(
                pool,
                abi.encodeCall(ICurvePoolLike.add_liquidity, (depositAmounts, minLpAmount, proxy))
            ),
            (uint256)
        );

        _applySwapRateLimit(pool, depositAmounts, rates, shares);

        emit CurveAddLiquidity(pool, shares, valueDeposited, depositAmounts);
    }

    function removeLiquidity(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256[] memory withdrawnTokens)
    {
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

        address proxy = _getSharedControllerStorage().proxy;

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

        _decreaseRateLimit(LIMIT_WITHDRAW, pool, valueWithdrawn);

        emit CurveRemoveLiquidity(pool, lpBurnAmount, valueWithdrawn, withdrawnTokens);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getMaxSlippage(address pool) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[pool];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approve(address token, address pool, uint256 amount) internal {
        ApproveLib.approve(token, _getSharedControllerStorage().proxy, pool, amount);
    }

    function _applySwapRateLimit(
        address            pool,
        uint256[] calldata depositAmounts,
        uint256[] memory   rates,
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
        _decreaseRateLimit(LIMIT_SWAP, pool, totalSwapped / 2);
    }

    function _decreaseRateLimit(bytes32 key, address pool, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(key, pool),
            amount
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _getExchangeCalldata(
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeCall(
            ICurvePoolLike.exchange,
            (
                int128(int256(inputIndex)),   // Safe cast because of 8 token max.
                int128(int256(outputIndex)),  // Safe cast because of 8 token max.
                amountIn,
                minAmountOut,
                _getSharedControllerStorage().proxy
            )
        );
    }

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

    function _fromNormalizedAmount(uint256 value, uint256 rate) internal pure returns (uint256) {
        return value * 1e18 / rate;
    }

    function _toNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * rate / 1e18;
    }

}
