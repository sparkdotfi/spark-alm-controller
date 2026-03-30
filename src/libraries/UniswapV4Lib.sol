// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Currency } from "../../lib/uniswap-v4-periphery/lib/v4-core/src/types/Currency.sol";
import { PoolKey }  from "../../lib/uniswap-v4-periphery/lib/v4-core/src/types/PoolKey.sol";

import { IV4Router }    from "../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";
import { Actions }      from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { IERC20Like, IPermit2Like }                   from "../interfaces/Common.sol";
import { IALMProxy }                                  from "../interfaces/IALMProxy.sol";
import { IRateLimits }                                from "../interfaces/IRateLimits.sol";
import { IPositionManagerLike, IUniversalRouterLike } from "../interfaces/UniswapV4.sol";
import { IUniswapV4Facet }                            from "../interfaces/facets/IUniswapV4Facet.sol";

import { makeBytes32Key } from "../RateLimitHelpers.sol";

import { FacetBase } from "./FacetBase.sol";

contract UniswapV4Facet is IUniswapV4Facet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.UniswapV4Facet
    struct FacetStorage {
        mapping(bytes32 poolId => uint256 maxSlippage) maxSlippages;
        mapping(bytes32 poolId => TickLimits limits) tickLimits;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.UniswapV4Facet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x87da7e510f1adf4bc390fc0575bbe3322b02f09a7fcc1a080301dab0c47ade00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");
    bytes32 public constant LIMIT_SWAP     = keccak256("LIMIT_UNISWAP_V4_SWAP");

    uint256 internal constant _V4_SWAP = 0x10;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable permit2;
    address public immutable positionManager;
    address public immutable router;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address permit2_, address positionManager_, address router_) {
        permit2         = permit2_;
        positionManager = positionManager_;
        router          = router_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setMaxSlippage(bytes32 poolId, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(poolId != bytes32(0), "UniswapV4Facet/zero-pool-id");

        emit UniswapV4MaxSlippageSet(poolId, _getFacetStorage().maxSlippages[poolId] = maxSlippage);
    }

    function setTickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            ((tickLowerMin == 0) && (tickUpperMax == 0) && (maxTickSpacing == 0)) ||
            ((maxTickSpacing > 0) && (tickLowerMin < tickUpperMax)),
            "UniswapV4Facet/invalid-ticks"
        );

        _getFacetStorage().tickLimits[poolId] = TickLimits({
            tickLowerMin   : tickLowerMin,
            tickUpperMax   : tickUpperMax,
            maxTickSpacing : maxTickSpacing
        });

        emit UniswapV4TickLimitsSet(poolId, tickLowerMin, tickUpperMax, maxTickSpacing);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function mintPosition(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _checkTickLimits(poolId, tickLower, tickUpper);

        PoolKey memory poolKey = _getPoolKeyFromPoolId(poolId);

        _requirePoolIdMatch(poolId, poolKey);

        bytes memory callData = _getMintCalldata({
            poolKey    : poolKey,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });

        _increaseLiquidity({
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });
    }

    function increasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        // Must not increase liquidity on a position that is not owned by the ALMProxy.
        require(
            IPositionManagerLike(positionManager).ownerOf(tokenId) ==
            _getSharedControllerStorage().proxy,
            "UniswapV4Facet/non-proxy-position"
        );

        ( PoolKey memory poolKey, PositionInfo info ) = _getPoolKeyAndPositionInfo(tokenId);

        _requirePoolIdMatch(poolId, poolKey);

        // Since funds are being added to the position, the ticks of the position need to be checked
        // against the current constraints, since it's possible the position was minted under
        // outdated tick limits, or was transferred to the proxy.
        _checkTickLimits(poolId, info.tickLower(), info.tickUpper());

        bytes memory callData = _getIncreaseLiquidityCallData({
            poolKey           : poolKey,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max
        });

        _increaseLiquidity({
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });
    }

    function decreasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        PoolKey memory poolKey = _getPoolKeyFromTokenId(tokenId);

        // NOTE: No need to check the token ownership here, as the proxy will be defined as the
        //       recipient of the tokens, so the worst case is that another account's position is
        //       decreased or closed by the proxy.
        _requirePoolIdMatch(poolId, poolKey);

        bytes memory callData = _getDecreaseLiquidityCallData({
            poolKey           : poolKey,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });

        _decreaseLiquidity({
            poolId   : poolId,
            token0   : Currency.unwrap(poolKey.currency0),
            token1   : Currency.unwrap(poolKey.currency1),
            callData : callData
        });
    }

    function swap(bytes32 poolId, address tokenIn, uint128 amountIn, uint128 amountOutMin)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[poolId];

        require(maxSlippage != 0, "UniswapV4Facet/max-slippage-not-set");

        PoolKey memory poolKey = _getPoolKeyFromPoolId(poolId);

        _requirePoolIdMatch(poolId, poolKey);

        require(
            tokenIn == Currency.unwrap(poolKey.currency0) ||
            tokenIn == Currency.unwrap(poolKey.currency1),
            "UniswapV4Facet/invalid-tokenIn"
        );

        uint256 normalizedAmountIn = _getNormalizedBalance(tokenIn, amountIn);

        // Perform rate limit decrease.
        // NOTE: Rate limit decrease does not account for the net amount of tokenIn actually taken.
        _decreaseRateLimit(LIMIT_SWAP, poolId, normalizedAmountIn);

        address tokenOut = tokenIn == Currency.unwrap(poolKey.currency0)
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);

        require(
            _getNormalizedBalance(tokenOut, amountOutMin) * 1e18 >=
            normalizedAmountIn * maxSlippage,
            "UniswapV4Facet/amountOutMin-too-low"
        );

        bytes memory callData = _getSwapCallData({
            poolKey      : poolKey,
            tokenIn      : tokenIn,
            tokenOut     : tokenOut,
            amountIn     : amountIn,
            amountOutMin : amountOutMin
        });

        _swap({
            poolId   : poolId,
            tokenIn  : tokenIn,
            amountIn : amountIn,
            callData : callData
        });
    }

    /**********************************************************************************************/
    /*** External View/Pure functions                                                           ***/
    /**********************************************************************************************/

    function getMaxSlippage(bytes32 poolId) external view returns (uint256) {
        return _getFacetStorage().maxSlippages[poolId];
    }

    function getTickLimits(bytes32 poolId)
        external
        view
        returns (int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing)
    {
        TickLimits storage tickLimits = _getFacetStorage().tickLimits[poolId];

        return (tickLimits.tickLowerMin, tickLimits.tickUpperMax, tickLimits.maxTickSpacing);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approveWithPermit2(address proxy, address token, address spender, uint128 amount)
        internal
    {
        // Approve the Permit2 contract to spend none of the token (success is optional).
        // NOTE: We don't care about the success of this call, since the only outcomes are:
        //         - the allowance is 0 (it was reset or was already 0)
        //         - the allowance is not 0, in which case the success of the overall set of
        //           operations is dependent on the success of the subsequent calls.
        //       In other words, this is a convenience call that may not even be needed for success.
        proxy.call(
            abi.encodeCall(
                IALMProxy.doCall,
                (token, abi.encodeCall(IERC20Like.approve, (permit2, 0)))
            )
        );

        if (amount != 0) {
            // Approve the Permit2 contract to spend the amount of token (success is mandatory).
            bytes memory approveResult = IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC20Like.approve, (permit2, amount))
            );

            // Revert if approve returns anything, and that anything is not `true`.
            require(
                approveResult.length == 0 ||
                (approveResult.length == 32 && abi.decode(approveResult, (bool))),
                "UniswapV4Facet/permit2-approve-failed"
            );
        }

        // Finally, approve the spender to spend the token via Permit2.
        IALMProxy(proxy).doCall(
            permit2,
            abi.encodeCall(
                IPermit2Like.approve,
                (token, spender, uint160(amount), uint48(block.timestamp))
            )
        );
    }

    function _increaseLiquidity(
        bytes32        poolId,
        address        token0,
        address        token1,
        uint128        amount0Max,
        uint128        amount1Max,
        bytes   memory callData
    )
        internal
    {
        address proxy = _getSharedControllerStorage().proxy;

        _approveWithPermit2(proxy, token0, positionManager, amount0Max);
        _approveWithPermit2(proxy, token1, positionManager, amount1Max);

        // Get token balances before liquidity increase.
        uint256 startingBalance0 = _getBalance(token0, proxy);
        uint256 startingBalance1 = _getBalance(token1, proxy);

        // Perform action
        IALMProxy(proxy).doCall(positionManager, callData);

        // Get token balances after liquidity increase.
        uint256 endingBalance0 = _getBalance(token0, proxy);
        uint256 endingBalance1 = _getBalance(token1, proxy);

        // Account for the theoretical possibility of receiving tokens when adding liquidity by
        // using a clamped subtraction.
        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.000000 USDC = 1.000000000000000000 USDS).
        uint256 rateLimitDecrease = _clampedSub(
            _getNormalizedBalance(token0, startingBalance0) +
            _getNormalizedBalance(token1, startingBalance1),
            _getNormalizedBalance(token0, endingBalance0) +
            _getNormalizedBalance(token1, endingBalance1)
        );

        // Perform rate limit decrease.
        // NOTE: Rate limit decrease is net of any token0 or token1 received due to fees.
        _decreaseRateLimit(LIMIT_DEPOSIT, poolId, rateLimitDecrease);

        // Reset approvals for token0 and token1.
        _approveWithPermit2(proxy, token0, positionManager, 0);
        _approveWithPermit2(proxy, token1, positionManager, 0);
    }

    function _decreaseLiquidity(
        bytes32        poolId,
        address        token0,
        address        token1,
        bytes   memory callData
    )
        internal
    {
        address proxy = _getSharedControllerStorage().proxy;

        // Get token balances before liquidity decrease.
        uint256 startingBalance0 = _getBalance(token0, proxy);
        uint256 startingBalance1 = _getBalance(token1, proxy);

        // Perform action.
        IALMProxy(proxy).doCall(positionManager, callData);

        // Get token balances after liquidity decrease.
        uint256 endingBalance0 = _getBalance(token0, proxy);
        uint256 endingBalance1 = _getBalance(token1, proxy);

        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.000000 USDC = 1.000000000000000000 USDS).
        uint256 rateLimitDecrease =
            _getNormalizedBalance(token0, endingBalance0 - startingBalance0) +
            _getNormalizedBalance(token1, endingBalance1 - startingBalance1);

        // Perform rate limit decrease.
        // NOTE: Rate limit decrease includes any token0 or token1 received due to fees.
        _decreaseRateLimit(LIMIT_WITHDRAW, poolId, rateLimitDecrease);
    }

    function _swap(bytes32 poolId, address tokenIn, uint128 amountIn, bytes memory callData)
        internal
    {
        address proxy = _getSharedControllerStorage().proxy;

        _approveWithPermit2(proxy, tokenIn, router, amountIn);

        // Perform action.
        IALMProxy(proxy).doCall(router, callData);

        // Reset approval of Permit2 in tokenIn.
        _approveWithPermit2(proxy, tokenIn, router, 0);
    }

    function _decreaseRateLimit(bytes32 key, bytes32 poolId, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeBytes32Key(key, poolId),
            amount
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _checkTickLimits(bytes32 poolId, int24 tickLower, int24 tickUpper)
        internal
        view
    {
        TickLimits storage tickLimits = _getFacetStorage().tickLimits[poolId];

        require(tickLimits.maxTickSpacing != 0,       "UniswapV4Facet/tickLimits-not-set");
        require(tickLower < tickUpper,                "UniswapV4Facet/ticks-misordered");
        require(tickLower >= tickLimits.tickLowerMin, "UniswapV4Facet/tickLower-too-low");
        require(tickUpper <= tickLimits.tickUpperMax, "UniswapV4Facet/tickUpper-too-high");

        require(
            uint256(int256(tickUpper) - int256(tickLower)) <= tickLimits.maxTickSpacing,
            "UniswapV4Facet/tickSpacing-too-wide"
        );
    }

    function _clampedSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        return a > b ? a - b : 0;
    }

    function _getBalance(address token, address account) internal view returns (uint256 balance) {
        return IERC20Like(token).balanceOf(account);
    }

    function _getMintCalldata(
        PoolKey memory poolKey,
        int24          tickLower,
        int24          tickUpper,
        uint128        liquidity,
        uint128        amount0Max,
        uint128        amount1Max
    )
        internal
        view
        returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            poolKey,                             // Which pool to mint in
            tickLower,                           // Position's lower price bound
            tickUpper,                           // Position's upper price bound
            uint256(liquidity),                  // Amount of liquidity to mint
            amount0Max,                          // Maximum amount of token0 to use
            amount1Max,                          // Maximum amount of token1 to use
            _getSharedControllerStorage().proxy, // NFT recipient
            ""                                   // No hook data needed
        );

        params[1] = abi.encode(poolKey.currency0); // First token to close
        params[2] = abi.encode(poolKey.currency1); // Second token to close

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getIncreaseLiquidityCallData(
        PoolKey memory poolKey,
        uint256        tokenId,
        uint128        liquidityIncrease,
        uint128        amount0Max,
        uint128        amount1Max
    )
        internal
        view
        returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            tokenId,                     // Position to increase
            uint256(liquidityIncrease),  // Amount to add
            amount0Max,                  // Maximum token0 to spend
            amount1Max,                  // Maximum token1 to spend
            ""                           // No hook data needed
        );

        params[1] = abi.encode(poolKey.currency0); // First token to close
        params[2] = abi.encode(poolKey.currency1); // Second token to close

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getDecreaseLiquidityCallData(
        PoolKey memory poolKey,
        uint256        tokenId,
        uint128        liquidityDecrease,
        uint128        amount0Min,
        uint128        amount1Min
    )
        internal
        view
        returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            tokenId,                     // Position to decrease
            uint256(liquidityDecrease),  // Amount to remove
            amount0Min,                  // Minimum token0 to receive
            amount1Min,                  // Minimum token1 to receive
            ""                           // No hook data needed
        );

        params[1] = abi.encode(
            poolKey.currency0,                  // First token
            poolKey.currency1,                  // Second token
            _getSharedControllerStorage().proxy // Who receives the tokens
        );

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getModifyLiquiditiesCallData(bytes memory actions, bytes[] memory params)
        internal
        view
        returns (bytes memory callData)
    {
        return abi.encodeCall(
            IPositionManagerLike.modifyLiquidities,
            (abi.encode(actions, params), block.timestamp)
        );
    }

    function _getSwapCallData(
        PoolKey memory poolKey,
        address        tokenIn,
        address        tokenOut,
        uint128        amountIn,
        uint128        amountOutMin
    )
        internal
        view
        returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey          : poolKey,
                zeroForOne       : tokenIn == Currency.unwrap(poolKey.currency0),
                amountIn         : amountIn,
                amountOutMinimum : amountOutMin,
                hookData         : bytes("")
            })
        );

        params[1] = abi.encode(tokenIn,  amountIn);
        params[2] = abi.encode(tokenOut, amountOutMin);

        // Combine actions and params into inputs.
        bytes[] memory inputs = new bytes[](1);

        inputs[0] = abi.encode(actions, params);

        return abi.encodeCall(
            IUniversalRouterLike.execute,
            (abi.encodePacked(uint8(_V4_SWAP)), inputs, block.timestamp)
        );
    }

    function _getNormalizedBalance(address token, uint256 balance)
        internal
        view
        returns (uint256 normalizedBalance)
    {
        return balance * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _getPoolKeyAndPositionInfo(uint256 tokenId)
        internal
        view
        returns (PoolKey memory poolKey, PositionInfo info)
    {
        return IPositionManagerLike(positionManager).getPoolAndPositionInfo(tokenId);
    }

    function _getPoolKeyFromPoolId(bytes32 poolId) internal view returns (PoolKey memory poolKey) {
        return IPositionManagerLike(positionManager).poolKeys(bytes25(poolId));
    }

    function _getPoolKeyFromTokenId(uint256 tokenId)
        internal
        view
        returns (PoolKey memory poolKey)
    {
        (poolKey, ) = _getPoolKeyAndPositionInfo(tokenId);
    }

    function _requirePoolIdMatch(bytes32 poolId, PoolKey memory poolKey) internal pure {
        require(keccak256(abi.encode(poolKey)) == poolId, "UniswapV4Facet/poolKey-poolId-mismatch");
    }

}
