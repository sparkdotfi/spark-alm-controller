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

    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    )
        external
        returns (uint256 tokensOut);

    function remove_liquidity(
        uint256            burnAmount,
        uint256[] calldata minAmounts,
        address            receiver
    )
        external;

    function N_COINS() external view returns (uint256);

    function balances(uint256 index) external view returns (uint256);

    function coins(uint256 index) external view returns (address);

    function get_virtual_price() external view returns (uint256);

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
        ( address tokenIn, address tokenOut ) = _getSwapTokens(pool, inputIndex, outputIndex);

        _decreaseRateLimit(getSwapRateLimitKey(pool, tokenIn), amountIn);

        _approve(tokenIn, pool, amountIn);

        bytes memory callData = _getExchangeCalldata({
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut
        });

        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingBalance = IERC20Like(tokenOut).balanceOf(proxy);

        IALMProxy(proxy).doCall(pool, callData);

        amountOut = IERC20Like(tokenOut).balanceOf(proxy) - startingBalance;

        // Clear approvals
        _approve(tokenIn, pool, 0);

        _validateSwap(
            pool,
            rates[inputIndex],
            rates[outputIndex],
            amountIn,
            minAmountOut,
            amountOut
        );

        emit CurveSwap(pool, inputIndex, outputIndex, amountIn, amountOut);
    }

    /// @inheritdoc ICurveFacet
    function addLiquidity(address pool, uint256[] calldata inputAmounts, uint256 minShares)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 shares)
    {
        uint256 virtualPrice = ICurvePoolLike(pool).get_virtual_price();

        // Prevent adding liquidity to unseeded pools.
        require(virtualPrice != 0, "CurveFacet/virtual-price-zero");

        address[] memory tokens = _getTokens(pool);

        require(inputAmounts.length == tokens.length, "CurveFacet/invalid-deposit-amounts");

        for (uint256 i = 0; i < inputAmounts.length; ++i) {
            _approve(tokens[i], pool, inputAmounts[i]);
        }

        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingShares = ICurvePoolLike(pool).balanceOf(proxy);

        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(ICurvePoolLike.add_liquidity, (inputAmounts, minShares, proxy))
        );

        shares = ICurvePoolLike(pool).balanceOf(proxy) - startingShares;

        // Clear approvals
        for (uint256 i = 0; i < tokens.length; ++i) {
            _approve(tokens[i], pool, 0);
        }

        _validateAddLiquidity(pool, virtualPrice, inputAmounts, rates, minShares, shares);

        int256[] memory swappedInAmounts = _getSwappedInAmounts(pool, inputAmounts, shares);

        _decreaseSwapRateLimits(pool, tokens, swappedInAmounts);

        _decreaseDepositRateLimits(
            pool,
            tokens,
            _getDepositedAmounts(inputAmounts, swappedInAmounts),
            rates
        );

        emit CurveAddLiquidity(pool, shares, inputAmounts);
    }

    /// @inheritdoc ICurveFacet
    function removeLiquidity(
        address            pool,
        uint256            shares,
        uint256[] calldata minWithdrawAmounts
    )
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256[] memory withdrawnAmounts)
    {
        uint256 virtualPrice = ICurvePoolLike(pool).get_virtual_price();

        require(
            minWithdrawAmounts.length == ICurvePoolLike(pool).N_COINS(),
            "CurveFacet/invalid-min-withdraw-amounts"
        );

        uint256[] memory rates = ICurvePoolLike(pool).stored_rates();

        address[] memory tokens           = _getTokens(pool);
        uint256[] memory startingBalances = new uint256[](tokens.length);

        address proxy = _getSharedControllerStorage().proxy;

        for (uint256 i = 0; i < minWithdrawAmounts.length; ++i) {
            startingBalances[i] = IERC20Like(tokens[i]).balanceOf(proxy);
        }

        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(
                ICurvePoolLike.remove_liquidity,
                (shares, minWithdrawAmounts, proxy)
            )
        );

        withdrawnAmounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            withdrawnAmounts[i] = IERC20Like(tokens[i]).balanceOf(proxy) - startingBalances[i];
        }

        _validateRemoveLiquidity(
            pool,
            virtualPrice,
            shares,
            minWithdrawAmounts,
            withdrawnAmounts,
            rates
        );

        _decreaseWithdrawRateLimit(pool, tokens, withdrawnAmounts, rates);

        emit CurveRemoveLiquidity(pool, shares, withdrawnAmounts);
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
    function getSwapRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_SWAP, token, pool);
    }

    /// @inheritdoc ICurveFacet
    function getAggregateWithdrawRateLimitKey(address pool) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_WITHDRAW, pool);
    }

    /// @inheritdoc ICurveFacet
    function getAssetWithdrawRateLimitKey(address pool, address token)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_WITHDRAW, token, pool);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approve(address token, address pool, uint256 amount) internal {
        ApproveLib.approve(token, _getSharedControllerStorage().proxy, pool, amount);
    }

    function _decreaseSwapRateLimits(address pool, address[] memory tokens, int256[] memory amounts)
        internal
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            _decreaseRateLimit(getSwapRateLimitKey(pool, tokens[i]), _clampUint256(amounts[i]));
        }
    }

    function _decreaseDepositRateLimits(
        address          pool,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory rates
    )
        internal
    {

        // NOTE: The aggregate amount is used for aggregate deposit rate limit decrease, which makes
        //       the assumption that the tokens are pegged and valued equally.
        //       (i.e. 1.000000 USDC = 1.000000000000000000 USDT). Aggregate rate limits should be
        //       set to "infinity" (`type(uint256).max`) for pools with unpegged tokens.
        uint256 aggregateAmount;

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amount = amounts[i];

            _decreaseRateLimit(getAssetDepositRateLimitKey(pool, tokens[i]), amount);

            aggregateAmount += _toNormalizedAmount(amount, rates[i]);
        }

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD).
        _decreaseRateLimit(getAggregateDepositRateLimitKey(pool), aggregateAmount);
    }

    function _decreaseWithdrawRateLimit(
        address          pool,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory rates
    )
        internal
    {
        // NOTE: The aggregate amount is used for aggregate withdrawal rate limit decrease, which
        //       makes the assumption that the tokens are pegged and valued equally.
        //       (i.e. 1.000000 USDC = 1.000000000000000000 USDT). Aggregate rate limits should be
        //       set to "infinity" (`type(uint256).max`) for pools with unpegged tokens.
        uint256 aggregateAmount;

        for (uint256 i = 0; i < amounts.length; ++i) {
            uint256 amount = amounts[i];

            _decreaseRateLimit(getAssetWithdrawRateLimitKey(pool, tokens[i]), amount);

            aggregateAmount += _toNormalizedAmount(amount, rates[i]);
        }

        _decreaseRateLimit(getAggregateWithdrawRateLimitKey(pool), aggregateAmount);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _clampUint256(int256 value) internal pure returns (uint256) {
        return value >= 0 ? uint256(value) : 0;
    }

    function _getSwappedInAmounts(
        address            pool,
        uint256[] calldata inputAmounts,
        uint256            shares
    ) internal view returns (int256[] memory swappedInAmounts) {
        swappedInAmounts = new int256[](inputAmounts.length);

        uint256 totalSupply = ICurvePoolLike(pool).totalSupply();

        // Compute the swap value by taking the difference of the current underlying asset values
        // from minted shares vs the deposited funds to find the tokens that were swapped in.
        for (uint256 i; i < inputAmounts.length; ++i) {
            uint256 resultingUnderlying = ICurvePoolLike(pool).balances(i) * shares / totalSupply;

            // Positive value means the asset was swapped in.
            swappedInAmounts[i] =
                _safeCastToInt256(inputAmounts[i]) -
                _safeCastToInt256(resultingUnderlying);
        }
    }

    function _getDepositedAmounts(uint256[] calldata inputAmounts, int256[] memory swappedInAmounts)
        internal
        pure
        returns (uint256[] memory depositedAmounts)
    {
        depositedAmounts = new uint256[](inputAmounts.length);

        for (uint256 i = 0; i < inputAmounts.length; ++i) {
            // A negative `swappedInAmounts[i]` implies that underlying balance was higher than the
            // input amount, so the deposit rate limit should be reduced by the full "deposited"
            // amount, which is the resulting underlying balance.
            int256 depositedAmount = _safeCastToInt256(inputAmounts[i]) - swappedInAmounts[i];

            // In practice this will not be possible, just adding as a safety check.
            if (depositedAmount <= 0) continue;

            depositedAmounts[i] = uint256(depositedAmount);
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

    function _fromNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * 1e18 / rate;
    }

    function _toNormalizedAmount(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return amount * rate / 1e18;
    }

    function _safeCastToInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "CurveFacet/int256-overflow");
        return int256(value);
    }

    function _getSwapTokens(address pool, uint256 inputIndex, uint256 outputIndex)
        internal
        view
        returns (address tokenIn, address tokenOut)
    {
        require(inputIndex != outputIndex, "CurveFacet/indices-equal");

        uint256 numCoins = ICurvePoolLike(pool).N_COINS();

        require(inputIndex < numCoins && outputIndex < numCoins, "CurveFacet/invalid-index");

        tokenIn  = ICurvePoolLike(pool).coins(inputIndex);
        tokenOut = ICurvePoolLike(pool).coins(outputIndex);
    }

    function _getTokens(address pool) internal view returns (address[] memory tokens) {
        tokens = new address[](ICurvePoolLike(pool).N_COINS());

        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i] = ICurvePoolLike(pool).coins(i);
        }
    }

    function _validateSwap(
        address pool,
        uint256 tokenInRate,
        uint256 tokenOutRate,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 amountOut
    )
        internal
        view
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        // Makes the assumption that value in should equal value out.
        uint256 equivalentAmountOut = _fromNormalizedAmount(
            _toNormalizedAmount(amountIn, tokenInRate),
            tokenOutRate
        );

        require(
            minAmountOut * 1e18 >= equivalentAmountOut * maxSlippage,
            "CurveFacet/min-amount-too-low"
        );

        require(amountOut >= minAmountOut, "CurveFacet/min-amount-not-met");
    }

    function _validateAddLiquidity(
        address            pool,
        uint256            virtualPrice,
        uint256[] calldata inputAmounts,
        uint256[] memory   rates,
        uint256            minShares,
        uint256            shares
    )
        internal
        view
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        uint256 inputValue;

        for (uint256 i = 0; i < inputAmounts.length; ++i) {
            inputValue += _toNormalizedAmount(inputAmounts[i], rates[i]);
        }

        // Ensure minimum LP amount expected is greater than max slippage amount.
        require(
            minShares * virtualPrice >= inputValue * maxSlippage,
            "CurveFacet/min-shares-too-low"
        );

        require(shares >= minShares, "CurveFacet/min-shares-not-met");
    }

    function _validateRemoveLiquidity(
        address            pool,
        uint256            virtualPrice,
        uint256            shares,
        uint256[] calldata minWithdrawAmounts,
        uint256[] memory   withdrawnAmounts,
        uint256[] memory   rates
    )
        internal
        view
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[pool];

        require(maxSlippage != 0, "CurveFacet/max-slippage-not-set");

        uint256 minWithdrawValue;

        for (uint256 i = 0; i < minWithdrawAmounts.length; ++i) {
            uint256 minWithdrawAmount = minWithdrawAmounts[i];

            require(withdrawnAmounts[i] >= minWithdrawAmount, "CurveFacet/min-amount-not-met");

            minWithdrawValue += _toNormalizedAmount(minWithdrawAmount, rates[i]);
        }

        // Check that the aggregated minimums are greater than the max slippage amount.
        require(
            minWithdrawValue * 1e36 >=
            shares * virtualPrice * maxSlippage,
            "CurveFacet/min-amounts-too-low"
        );
    }

}
