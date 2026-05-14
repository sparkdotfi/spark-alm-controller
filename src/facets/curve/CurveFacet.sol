// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ICurveFacet } from "./ICurveFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface ICurvePoolLike is IERC20Like {

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external;

    function balances(uint256 index) external view returns (uint256);

    function coins(uint256 index) external view returns (address);

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

contract CurveFacet is ICurveFacet, Facet {

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

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 internal constant _LIMIT_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc ICurveFacet
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
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc ICurveFacet
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
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 amountOut)
    {
        require(inputIndex != outputIndex, "CurveFacet/invalid-indices");

        uint256 numCoins = ICurvePoolLike(pool).N_COINS();

        require(inputIndex < numCoins && outputIndex < numCoins, "CurveFacet/index-too-high");

        _validateSwapMinAmountOut(pool, inputIndex, outputIndex, amountIn, minAmountOut);

        address tokenIn = ICurvePoolLike(pool).coins(inputIndex);

        _decreaseRateLimit(getSwapRateLimitKey(pool, tokenIn), amountIn);

        _approve(tokenIn, pool, amountIn);

        bytes memory callData = _getExchangeCalldata({
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut
        });

        address proxy    = _getSharedControllerStorage().proxy;
        address tokenOut = ICurvePoolLike(pool).coins(outputIndex);

        uint256 startingBalance = IERC20Like(tokenOut).balanceOf(proxy);

        IALMProxy(proxy).doCall(pool, callData);

        amountOut = IERC20Like(tokenOut).balanceOf(proxy) - startingBalance;

        // Clear approvals
        _approve(tokenIn, pool, 0);

        emit CurveSwap(pool, inputIndex, outputIndex, amountIn, amountOut);
    }

    /// @inheritdoc ICurveFacet
    function addLiquidity(address pool, uint256[] calldata depositAmounts, uint256 minLpAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 shares)
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        require(
            depositAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveFacet/invalid-deposit-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates  = ICurvePoolLike(pool).stored_rates();
        address[] memory tokens = new address[](depositAmounts.length);

        // Aggregate the value of the deposited assets (e.g. USD).
        uint256 valueDeposited;
        for (uint256 i = 0; i < depositAmounts.length; ++i) {
            uint256 depositAmount = depositAmounts[i];

            _approve(tokens[i] = ICurvePoolLike(pool).coins(i), pool, depositAmount);

            valueDeposited += depositAmount * rates[i];
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
        _decreaseRateLimit(getAggregateDepositRateLimitKey(pool), valueDeposited);

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingShares = ICurvePoolLike(pool).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(ICurvePoolLike.add_liquidity, (depositAmounts, minLpAmount, proxy))
        );

        shares = ICurvePoolLike(pool).balanceOf(proxy) - startingShares;

        _decreaseRateLimitsForAddLiquidity(pool, tokens, depositAmounts, shares);

        // Clear approvals
        for (uint256 i = 0; i < tokens.length; ++i) {
            _approve(tokens[i], pool, 0);
        }

        emit CurveAddLiquidity(pool, shares, valueDeposited, depositAmounts);
    }

    /// @inheritdoc ICurveFacet
    function removeLiquidity(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
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

        address[] memory tokens           = new address[](minWithdrawAmounts.length);
        uint256[] memory startingBalances = new uint256[](minWithdrawAmounts.length);

        // NOTE: Not rate limiting on the individual tokens (i.e. trusting the `coins` array) since
        //       the tokens of the pool are rate limited on deposit and the contract is immutable.
        for (uint256 i = 0; i < minWithdrawAmounts.length; ++i) {
            tokens[i]           = ICurvePoolLike(pool).coins(i);
            startingBalances[i] = IERC20Like(tokens[i]).balanceOf(proxy);
        }

        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(
                ICurvePoolLike.remove_liquidity,
                (lpBurnAmount, minWithdrawAmounts, proxy)
            )
        );

        withdrawnTokens = new uint256[](tokens.length);

        // Aggregate value withdrawn to reduce the rate limit.
        uint256 valueWithdrawn;
        for (uint256 i = 0; i < tokens.length; ++i) {
            withdrawnTokens[i] = IERC20Like(tokens[i]).balanceOf(proxy) - startingBalances[i];

            valueWithdrawn += withdrawnTokens[i] * rates[i];
        }
        valueWithdrawn /= 1e18;

        _decreaseRateLimit(getWithdrawRateLimitKey(pool), valueWithdrawn);

        emit CurveRemoveLiquidity(pool, lpBurnAmount, valueWithdrawn, withdrawnTokens);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ICurveFacet
    function getAggregateDepositRateLimitKey(address pool) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_DEPOSIT, pool);
    }

    /// @inheritdoc ICurveFacet
    function getAssetDepositRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_DEPOSIT, token, pool);
    }

    /// @inheritdoc ICurveFacet
    function getMaxSlippage(address pool) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[pool];
    }

    /// @inheritdoc ICurveFacet
    function getSwapRateLimitKey(address pool, address token) public pure override returns (bytes32) {
        return makeAddressAddressKey(_LIMIT_SWAP, token, pool);
    }

    /// @inheritdoc ICurveFacet
    function getWithdrawRateLimitKey(address pool) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_WITHDRAW, pool);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approve(address token, address pool, uint256 amount) internal {
        ApproveLib.approve(token, _getSharedControllerStorage().proxy, pool, amount);
    }

    function _decreaseRateLimitsForAddLiquidity(
        address            pool,
        address[] memory   tokens,
        uint256[] calldata depositAmounts,
        uint256            shares
    ) internal {
        // Compute the amount of each token that was swapped in (or out).
        int256[] memory swappedInAmounts = _getSwappedInAmounts(pool, depositAmounts, shares);

        // For each token, decrease the deposit rate limit by the amount of the token that were
        // actually deposited and the swap rate limit by the amount that was swapped in.
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];

            int256 swappedIn = swappedInAmounts[i];
            int256 deposited = _safeCastToInt256(depositAmounts[i]) - swappedIn;

            if (deposited > 0) {
                _decreaseRateLimit(getAssetDepositRateLimitKey(pool, token), uint256(deposited));
            }

            if (swappedIn > 0) {
                _decreaseRateLimit(getSwapRateLimitKey(pool, token), uint256(swappedIn));
            }
        }
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getSwappedInAmounts(
        address            pool,
        uint256[] calldata depositAmounts,
        uint256            shares
    ) internal view returns (int256[] memory swappedInAmounts) {
        swappedInAmounts = new int256[](depositAmounts.length);

        uint256 totalSupply = ICurvePoolLike(pool).totalSupply();

        // Compute the swap value by taking the difference of the current underlying asset values
        // from minted shares vs the deposited funds to find the tokens that were swapped in.
        for (uint256 i; i < depositAmounts.length; ++i) {
            uint256 resultingUnderlying = _getPoolBalance(pool, i) * shares / totalSupply;

            // Positive value means the asset was swapped in.
            swappedInAmounts[i] =
                _safeCastToInt256(depositAmounts[i]) -
                _safeCastToInt256(resultingUnderlying);
        }
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

    function _fromNormalizedAmount(uint256 value, uint256 rate) internal pure returns (uint256) {
        return value * 1e18 / rate;
    }

    function _toNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * rate / 1e18;
    }

    function _getPoolBalance(address pool, uint256 index) internal view returns (uint256) {
        return ICurvePoolLike(pool).balances(index);
    }

    function _safeCastToInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "CurveFacet/int256-overflow");
        return int256(value);
    }

    function _validateSwapMinAmountOut(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        internal
        view
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        // Normalized to provide 36 decimal precision when multiplied by asset amount.
        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        // Makes the assumption that value in should equal value out.
        uint256 equivalentAmountOut = _fromNormalizedAmount(
            _toNormalizedAmount(amountIn, rates[inputIndex]),
            rates[outputIndex]
        );

        require(
            minAmountOut >= equivalentAmountOut * maxSlippage / 1e18,
            "CurveFacet/min-amount-not-met"
        );
    }

}
