// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ICurveFacet
 * @notice PAU facet for interacting with Curve pools. Supports adding and removing liquidity, and
 *         token swaps. All value calculations use 18-decimal normalized USD amounts derived from
 *         Curve stored_rates.
 */
interface ICurveFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when liquidity is added to a Curve pool.
     * @param  pool           Address of the Curve pool.
     * @param  shares         Amount of LP tokens received.
     * @param  valueDeposited Aggregate deposited value, 18-decimal normalized USD.
     * @param  depositAmounts Per-token amounts deposited (native token decimals).
     */
    event CurveAddLiquidity(
        address   indexed pool,
        uint256           shares,
        uint256           valueDeposited,
        uint256[]         depositAmounts
    );

    /**
     * @notice Emitted when the max slippage for a Curve pool is updated.
     * @param  pool        Address of the Curve pool.
     * @param  maxSlippage New max slippage in 1e18 precision (1e18 = no slippage).
     */
    event CurveMaxSlippageSet(address indexed pool, uint256 maxSlippage);

    /**
     * @notice Emitted when liquidity is removed from a Curve pool.
     * @param  pool            Address of the Curve pool.
     * @param  lpBurnAmount    Amount of LP tokens burned.
     * @param  valueWithdrawn  Aggregate withdrawn value, 18-decimal normalized USD.
     * @param  withdrawnTokens Per-token amounts withdrawn (native token decimals).
     */
    event CurveRemoveLiquidity(
        address   indexed pool,
        uint256           lpBurnAmount,
        uint256           valueWithdrawn,
        uint256[]         withdrawnTokens
    );

    /**
     * @notice Emitted when a token swap is executed on a Curve pool.
     * @param  pool        Address of the Curve pool.
     * @param  inputIndex  Index of the input token in the pool.
     * @param  outputIndex Index of the output token in the pool.
     * @param  amountIn    Amount of input tokens swapped (native decimals).
     * @param  amountOut   Amount of output tokens received (native decimals).
     */
    event CurveSwap(
        address indexed pool,
        uint256 indexed inputIndex,
        uint256 indexed outputIndex,
        uint256         amountIn,
        uint256         amountOut
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Adds liquidity to a Curve pool.
     * @param  pool           Address of the Curve pool.
     * @param  depositAmounts Per-token amounts to deposit (native token decimals).
     * @param  minLpAmount    Minimum LP tokens to receive.
     * @return shares         Amount of LP tokens received.
     */
    function addLiquidity(address pool, uint256[] calldata depositAmounts, uint256 minLpAmount)
        external
        returns (uint256 shares);

    /**
     * @notice Removes liquidity from a Curve pool proportionally.
     * @param  pool               Address of the Curve pool.
     * @param  lpBurnAmount       Amount of LP tokens to burn.
     * @param  minWithdrawAmounts Per-token minimum amounts to receive.
     * @return withdrawnTokens    Per-token amounts actually withdrawn.
     */
    function removeLiquidity(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        returns (uint256[] memory withdrawnTokens);

    /**
     * @notice Sets the max slippage for a Curve pool.
     * @param  pool        Address of the Curve pool.
     * @param  maxSlippage Max slippage in 1e18 precision (1e18 = no slippage).
     */
    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    /**
     * @notice Swaps tokens within a Curve pool.
     * @param  pool         Address of the Curve pool.
     * @param  inputIndex   Index of the input token in the pool.
     * @param  outputIndex  Index of the output token in the pool.
     * @param  amountIn     Amount of input tokens to swap (native decimals).
     * @param  minAmountOut Minimum output tokens to receive (native decimals).
     * @return amountOut    Actual amount of output tokens received.
     */
    function swap(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived aggregate deposit rate limit key for a Curve pool.
     * @param  pool Address of the Curve pool.
     * @return key  Derived rate limit key.
     */
    function getAggregateDepositRateLimitKey(address pool) external pure returns (bytes32 key);

    /**
     * @notice Returns the derived asset deposit rate limit key for a Curve pool and token.
     * @param  pool  Address of the Curve pool.
     * @param  token Address of the token.
     * @return key   Derived rate limit key.
     */
    function getAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the configured max slippage for a Curve pool.
     * @param  pool        Address of the Curve pool.
     * @return maxSlippage Max slippage in 1e18 precision. Zero means not set.
     */
    function getMaxSlippage(address pool) external view returns (uint256 maxSlippage);

    /**
     * @notice Returns the derived swap rate limit key for a Curve pool and token.
     * @param  pool  Address of the Curve pool.
     * @param  token Address of the token.
     * @return key   Derived rate limit key.
     */
    function getSwapRateLimitKey(address pool, address token) external pure returns (bytes32 key);

    /**
     * @notice Returns the derived withdraw rate limit key for a Curve pool.
     * @param  pool Address of the Curve pool.
     * @return key  Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address pool) external pure returns (bytes32 key);

}
