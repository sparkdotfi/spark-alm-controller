// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Currency } from "../../../lib/uniswap-v4-periphery/lib/v4-core/src/types/Currency.sol";
import { PoolId }   from "../../../lib/uniswap-v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey }  from "../../../lib/uniswap-v4-periphery/lib/v4-core/src/types/PoolKey.sol";

import { IV4Router } from "../../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";
import { Actions }   from "../../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";

import {
    PositionInfo
} from "../../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeBytes32Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IUniswapV4Facet } from "./IUniswapV4Facet.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

}

interface IPositionManagerLike {

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    function getPoolAndPositionInfo(uint256 tokenId)
        external
        view
        returns (PoolKey memory, PositionInfo);

    function nextTokenId() external view returns (uint256);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory);

    function ownerOf(uint256 tokenId) external view returns (address);

}

interface IUniversalRouterLike {

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;

}

contract UniswapV4Facet is IUniswapV4Facet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.UniswapV4Facet.v1
    struct FacetStorage {
        mapping (bytes32 poolId => uint256    maxSlippage) maxSlippages;  // 1e18 precision
        mapping (bytes32 poolId => TickLimits limits)      tickLimits;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.UniswapV4Facet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x2ce6552ef43d5442d5a2e9633c16b55e669383de0d79e2922fe0aaf476410200;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV4Facet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");

    /// @inheritdoc IUniswapV4Facet
    bytes32 public constant override LIMIT_SWAP = keccak256("LIMIT_UNISWAP_V4_SWAP");

    /// @inheritdoc IUniswapV4Facet
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    uint256 internal constant _V4_SWAP = 0x10;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV4Facet
    address public immutable override permit2;

    /// @inheritdoc IUniswapV4Facet
    address public immutable override positionManager;

    /// @inheritdoc IUniswapV4Facet
    address public immutable override router;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address permit2_, address positionManager_, address router_) {
        require(permit2_         != address(0), "UniswapV4Facet/zero-permit2");
        require(positionManager_ != address(0), "UniswapV4Facet/zero-position-manager");
        require(router_          != address(0), "UniswapV4Facet/zero-router");

        permit2         = permit2_;
        positionManager = positionManager_;
        router          = router_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV4Facet
    function setMaxSlippage(bytes32 poolId, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(poolId != bytes32(0), "UniswapV4Facet/zero-pool-id");

        emit UniswapV4MaxSlippageSet(poolId, _getFacetStorage().maxSlippages[poolId] = maxSlippage);
    }

    /// @inheritdoc IUniswapV4Facet
    function setTickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external
        override
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

    /// @inheritdoc IUniswapV4Facet
    function mintPosition(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        override
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

        ( uint128 amount0, uint128 amount1 ) = _increaseLiquidity({
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });

        emit UniswapV4MintPosition(
            poolId,
            IPositionManagerLike(positionManager).nextTokenId() - 1,
            tickLower,
            tickUpper,
            liquidity,
            amount0,
            amount1
        );
    }

    /// @inheritdoc IUniswapV4Facet
    function increasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        override
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

        ( uint128 amount0, uint128 amount1 ) = _increaseLiquidity({
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });

        emit UniswapV4IncreasePosition(poolId, tokenId, liquidityIncrease, amount0, amount1);
    }

    /// @inheritdoc IUniswapV4Facet
    function decreasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external
        override
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

        ( uint128 amount0, uint128 amount1 ) = _decreaseLiquidity({
            poolId   : poolId,
            token0   : Currency.unwrap(poolKey.currency0),
            token1   : Currency.unwrap(poolKey.currency1),
            callData : callData
        });

        emit UniswapV4DecreasePosition(poolId, tokenId, liquidityDecrease, amount0, amount1);
    }

    /// @inheritdoc IUniswapV4Facet
    function swap(bytes32 poolId, address tokenIn, uint128 amountIn, uint128 amountOutMin)
        external
        override
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

        uint128 amountOut = _swap({
            poolId   : poolId,
            tokenIn  : tokenIn,
            tokenOut : tokenOut,
            amountIn : amountIn,
            callData : callData
        });

        emit UniswapV4Swap(poolId, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUniswapV4Facet
    function getMaxSlippage(bytes32 poolId) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[poolId];
    }

    /// @inheritdoc IUniswapV4Facet
    function getTickLimits(bytes32 poolId)
        external
        view
        override
        returns (int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing)
    {
        TickLimits storage tickLimits = _getFacetStorage().tickLimits[poolId];

        return (tickLimits.tickLowerMin, tickLimits.tickUpperMax, tickLimits.maxTickSpacing);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approveWithPermit2(address token, address spender, uint128 amount) internal {
        address proxy = _getSharedControllerStorage().proxy;

        // Approve the Permit2 contract to spend the amount of token.
        ApproveLib.approve(token, proxy, permit2, amount);

        // Approve the spender to spend the token via Permit2.
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
        returns (uint128 amount0, uint128 amount1)
    {
        _approveWithPermit2(token0, positionManager, amount0Max);
        _approveWithPermit2(token1, positionManager, amount1Max);

        // Get token balances before liquidity increase.
        uint256 startingBalance0 = _getProxyBalance(token0);
        uint256 startingBalance1 = _getProxyBalance(token1);

        // Perform action
        IALMProxy(_getSharedControllerStorage().proxy).doCall(positionManager, callData);

        // Get token balances after liquidity increase.
        uint256 endingBalance0 = _getProxyBalance(token0);
        uint256 endingBalance1 = _getProxyBalance(token1);

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
        _approveWithPermit2(token0, positionManager, 0);
        _approveWithPermit2(token1, positionManager, 0);

        amount0 = uint128(_clampedSub(startingBalance0, endingBalance0));
        amount1 = uint128(_clampedSub(startingBalance1, endingBalance1));
    }

    function _decreaseLiquidity(
        bytes32        poolId,
        address        token0,
        address        token1,
        bytes   memory callData
    )
        internal
        returns (uint128 amount0, uint128 amount1)
    {
        // Get token balances before liquidity decrease.
        uint256 startingBalance0 = _getProxyBalance(token0);
        uint256 startingBalance1 = _getProxyBalance(token1);

        // Perform action.
        IALMProxy(_getSharedControllerStorage().proxy).doCall(positionManager, callData);

        // Get token balances after liquidity decrease.
        amount0 = uint128(_getProxyBalance(token0) - startingBalance0);
        amount1 = uint128(_getProxyBalance(token1) - startingBalance1);

        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.000000 USDC = 1.000000000000000000 USDS).
        uint256 rateLimitDecrease =
            _getNormalizedBalance(token0, amount0) +
            _getNormalizedBalance(token1, amount1);

        // Perform rate limit decrease.
        // NOTE: Rate limit decrease includes any token0 or token1 received due to fees.
        _decreaseRateLimit(LIMIT_WITHDRAW, poolId, rateLimitDecrease);
    }

    function _swap(
        bytes32        poolId,
        address        tokenIn,
        address        tokenOut,
        uint128        amountIn,
        bytes   memory callData
    )
        internal
        returns (uint128 amountOut)
    {
        _approveWithPermit2(tokenIn, router, amountIn);

        uint256 startingBalance = _getProxyBalance(tokenOut);

        // Perform action.
        IALMProxy(_getSharedControllerStorage().proxy).doCall(router, callData);

        // Reset approval of Permit2 in tokenIn.
        _approveWithPermit2(tokenIn, router, 0);

        return uint128(_getProxyBalance(tokenOut) - startingBalance);
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

    function _getProxyBalance(address token) internal view returns (uint256 balance) {
        return IERC20Like(token).balanceOf(_getSharedControllerStorage().proxy);
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
