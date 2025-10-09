// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { console } from "../../lib/forge-std/src/console.sol";

import { FullMath } from "../../lib/uniswap-v4-core/src/libraries/FullMath.sol";
import { TickMath } from "../../lib/uniswap-v4-core/src/libraries/TickMath.sol";

import { Currency } from "../../lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolId }   from "../../lib/uniswap-v4-core/src/types/PoolId.sol";
import { PoolKey }  from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";

import { Actions }      from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { IERC20Like, IPermit2Like }             from "../interfaces/Common.sol";
import { IALMProxy }                            from "../interfaces/IALMProxy.sol";
import { IRateLimits }                          from "../interfaces/IRateLimits.sol";
import { IPositionManagerLike, IStateViewLike } from "../interfaces/UniswapV4.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library UniswapV4Lib {

    struct CommonParams {
        address proxy;
        address rateLimits;
        bytes32 rateLimitId;
        uint256 maxSlippage;
        bytes32 poolId;  // the PoolId of the Uniswap V4 pool
    }

    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments
    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _STATE_VIEW       = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function mintPosition(
        CommonParams calldata commonParams,
        int24                 tickLower,
        int24                 tickUpper,
        uint128               liquidity,
        uint256               amount0Max,
        uint256               amount1Max
    ) external returns (uint256 rateLimitDecrease) {
        _validateLiquidityIncrease({
            commonParams      : commonParams,
            tickLower         : tickLower,
            tickUpper         : tickUpper,
            liquidityIncrease : liquidity,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max
        });

        // Encode actions and params
        PoolKey memory poolKey = IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(commonParams.poolId));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            poolKey,             // Which pool to mint in
            tickLower,           // Position's lower price bound
            tickUpper,           // Position's upper price bound
            liquidity,           // Amount of liquidity to mint
            amount0Max,          // Maximum amount of token0 to use
            amount1Max,          // Maximum amount of token1 to use
            commonParams.proxy,  // NFT recipient
            ""                   // No hook data needed
        );

        params[1] = abi.encode(
            poolKey.currency0,  // First token to settle
            poolKey.currency1   // Second token to settle
        );

        return _increaseLiquidity({
            commonParams : commonParams,
            token0       : Currency.unwrap(poolKey.currency0),
            token1       : Currency.unwrap(poolKey.currency1),
            amount0Max   : amount0Max,
            amount1Max   : amount1Max,
            actions      : actions,
            params       : params
        });
    }

    function increasePosition(
        CommonParams calldata commonParams,
        uint256               tokenId,
        uint128               liquidityIncrease,
        uint256               amount0Max,
        uint256               amount1Max
    ) external returns (uint256 rateLimitDecrease) {
        // The proxy must be the position owner to retain ownership of the increased liquidity.
        require(
            IPositionManagerLike(_POSITION_MANAGER).ownerOf(tokenId) == commonParams.proxy,
            "UniswapV4Lib/non-proxy-position"
        );

        (
            PoolKey      memory poolKey,
            PositionInfo        positionInfo
        ) = _getPositionInfo(commonParams.poolId, tokenId);

        _validateLiquidityIncrease({
            commonParams      : commonParams,
            tickLower         : positionInfo.tickLower(),
            tickUpper         : positionInfo.tickUpper(),
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            tokenId,              // Position to increase
            liquidityIncrease,    // Amount to add
            amount0Max,           // Maximum token0 to spend
            amount1Max,           // Maximum token1 to spend
            ""                    // No hook data needed
        );

        params[1] = abi.encode(poolKey.currency0);
        params[2] = abi.encode(poolKey.currency1);

        return _increaseLiquidity({
            commonParams : commonParams,
            token0       : Currency.unwrap(poolKey.currency0),
            token1       : Currency.unwrap(poolKey.currency1),
            amount0Max   : amount0Max,
            amount1Max   : amount1Max,
            actions      : actions,
            params       : params
        });
    }

    function burnPosition(
        CommonParams calldata commonParams,
        uint256               tokenId,
        uint256               amount0Min,
        uint256               amount1Min
    ) external returns (uint256 rateLimitDecrease) {
        (
            PoolKey      memory poolKey,
            PositionInfo        positionInfo
        ) = _getPositionInfo(commonParams.poolId, tokenId);

        uint128 liquidity = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        _validateLiquidityDecrease({
            commonParams      : commonParams,
            tickLower         : positionInfo.tickLower(),
            tickUpper         : positionInfo.tickUpper(),
            liquidityDecrease : liquidity,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.BURN_POSITION),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            tokenId,     // Position to burn
            amount0Min,  // Minimum token0 to receive
            amount1Min,  // Minimum token1 to receive
            ""           // No hook data needed
        );

        params[1] = abi.encode(
            poolKey.currency0,  // First token
            poolKey.currency1,  // Second token
            commonParams.proxy  // Who receives the tokens
        );

        return _decreaseLiquidity({
            commonParams : commonParams,
            token0       : Currency.unwrap(poolKey.currency0),
            token1       : Currency.unwrap(poolKey.currency1),
            actions      : actions,
            params       : params
        });
    }

    function decreasePosition(
        CommonParams calldata commonParams,
        uint256               tokenId,
        uint128               liquidityDecrease,
        uint256               amount0Min,
        uint256               amount1Min
    ) external returns (uint256 rateLimitDecrease) {
        (
            PoolKey      memory poolKey,
            PositionInfo        positionInfo
        ) = _getPositionInfo(commonParams.poolId, tokenId);

        _validateLiquidityDecrease({
            commonParams      : commonParams,
            tickLower         : positionInfo.tickLower(),
            tickUpper         : positionInfo.tickUpper(),
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            tokenId,            // Position to decrease
            liquidityDecrease,  // Amount to remove
            amount0Min,         // Minimum token0 to receive
            amount1Min,         // Minimum token1 to receive
            ""                  // No hook data needed
        );

        params[1] = abi.encode(
            poolKey.currency0,  // First token
            poolKey.currency1,  // Second token
            commonParams.proxy  // Who receives the tokens
        );

        return _decreaseLiquidity({
            commonParams : commonParams,
            token0       : Currency.unwrap(poolKey.currency0),
            token1       : Currency.unwrap(poolKey.currency1),
            actions      : actions,
            params       : params
        });
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getAmountsForLiquidity(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(poolId));

        return getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
    }

    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) public pure returns (uint256 amount0, uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib/invalid-sqrtPrices");

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            return (
                _getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity),
                0
            );
        }

        if (sqrtPriceX96 >= sqrtPriceBX96) {
            return (
                0,
                _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity)
            );
        }

        return (
            _getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity),
            _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity)
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approvePositionManager(address proxy, address token, uint256 amount) internal {
        // First, approve the Permit2 contract to spend none of the token (success is optional).
        proxy.call(
            abi.encodeCall(
                IALMProxy.doCall,
                (token, abi.encodeCall(IERC20Like.approve, (_PERMIT2, 0)))
            )
        );

        if (amount != 0) {
            // Then, approve the Permit2 contract to spend the amount of token (success is mandatory).
            bytes memory approveResult = IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC20Like.approve, (_PERMIT2, amount))
            );

            // Revert if approve returns anything, and that anything is not `true`.
            require(
                approveResult.length == 0 || abi.decode(approveResult, (bool)),
                "UniswapV4Lib/permit2-approve-failed"
            );
        }

        // Finally, approve the Position Manager contract to spend the token via Permit2.
        IALMProxy(proxy).doCall(
            _PERMIT2,
            abi.encodeCall(
                IPermit2Like.approve,
                (token, _POSITION_MANAGER, uint160(amount), uint48(block.timestamp))
            )
        );
    }

    function _increaseLiquidity(
        CommonParams calldata commonParams,
        address               token0,
        address               token1,
        uint256               amount0Max,
        uint256               amount1Max,
        bytes        memory   actions,
        bytes[]      memory   params
    ) internal returns (uint256 rateLimitDecrease) {
        _approvePositionManager(commonParams.proxy, token0, amount0Max);
        _approvePositionManager(commonParams.proxy, token1, amount1Max);

        // Get token balances before mint.
        uint256 startingBalance0 = _getNormalizedBalance(token0, commonParams.proxy);
        uint256 startingBalance1 = _getNormalizedBalance(token1, commonParams.proxy);

        // Perform action
        IALMProxy(commonParams.proxy).doCall(
            _POSITION_MANAGER,
            abi.encodeCall(
                IPositionManagerLike.modifyLiquidities,
                (abi.encode(actions, params), block.timestamp)
            )
        );

        // Get token balances after mint.
        uint256 endingBalance0 = _getNormalizedBalance(token0, commonParams.proxy);
        uint256 endingBalance1 = _getNormalizedBalance(token1, commonParams.proxy);

        // Account for the theoretical possibility of receiving tokens when adding liquidity by
        // using a clamped subtraction.
        rateLimitDecrease = _clampedSub(
            startingBalance0 + startingBalance1,
            endingBalance0 + endingBalance1
        );

        // Perform rate limit decrease.
        IRateLimits(commonParams.rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(commonParams.rateLimitId, commonParams.poolId),
            rateLimitDecrease
        );

        // Reset approval of Permit2 in token0 and token1
        // NOTE: It's not necessary to reset the Position Manager approval in Permit2 (as it
        //       doesn't have allowance in the token at this point), but prudent so there isn't a
        //       hanging unused approval.
        _approvePositionManager(commonParams.proxy, token0, 0);
        _approvePositionManager(commonParams.proxy, token1, 0);
    }

    function _decreaseLiquidity(
        CommonParams calldata commonParams,
        address               token0,
        address               token1,
        bytes        memory   actions,
        bytes[]      memory   params
    ) internal returns (uint256 rateLimitDecrease) {
        // Get token balances before mint.
        uint256 startingBalance0 = _getNormalizedBalance(token0, commonParams.proxy);
        uint256 startingBalance1 = _getNormalizedBalance(token1, commonParams.proxy);

        // Perform action
        IALMProxy(commonParams.proxy).doCall(
            _POSITION_MANAGER,
            abi.encodeCall(
                IPositionManagerLike.modifyLiquidities,
                (abi.encode(actions, params), block.timestamp)
            )
        );

        // Get token balances after mint.
        uint256 endingBalance0 = _getNormalizedBalance(token0, commonParams.proxy);
        uint256 endingBalance1 = _getNormalizedBalance(token1, commonParams.proxy);

        // Perform rate limit decrease.
        // TODO: Not impossible that an increase is needed, given fees and a low liquidity increase.
        IRateLimits(commonParams.rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(commonParams.rateLimitId, commonParams.poolId),
            // Technically one can receive tokens when adding liquidity (if there are fees to be
            // accumulated, so safe/clamped/non-negative subtraction is needed here).
            rateLimitDecrease = endingBalance0 + endingBalance1 - startingBalance0 - startingBalance1
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _clampedSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        return a > b ? a - b : 0;
    }

    function _getAmount0ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib/invalid-sqrtPrices-0");

        return FullMath.mulDiv(
            uint256(liquidity) << 96,
            sqrtPriceBX96 - sqrtPriceAX96,
            uint256(sqrtPriceBX96) * sqrtPriceAX96
        );
    }

    function _getAmount1ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "UniswapV4Lib/invalid-sqrtPrices-1");

        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, 1 << 96);
    }

    function _getNormalizedBalance(
        address token,
        address account
    ) internal view returns (uint256 balance) {
        return IERC20Like(token).balanceOf(account) * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _getPositionInfo(
        bytes32 poolId,
        uint256 tokenId
    ) internal view returns (PoolKey memory poolKey, PositionInfo positionInfo) {
        (
            poolKey,
            positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        require(keccak256(abi.encode(poolKey)) == poolId, "UniswapV4Lib/tokenId-poolId-mismatch");
    }

    function _validateLiquidityIncrease(
        CommonParams calldata commonParams,
        int24                 tickLower,
        int24                 tickUpper,
        uint128               liquidityIncrease,
        uint256               amount0Max,
        uint256               amount1Max
    ) internal view {
        _requireNonZeroMaxSlippage(commonParams);

        ( uint256 amount0, uint256 amount1 ) = getAmountsForLiquidity(
            commonParams.poolId,
            tickLower,
            tickUpper,
            liquidityIncrease
        );

        // Ensure the amountMax is below the allowed worst case scenario (amount / maxSlippage).
        require(
            amount0Max * commonParams.maxSlippage <= amount0 * 1e18,
            "UniswapV4Lib/amount0Max-too-high"
        );

        require(
            amount1Max * commonParams.maxSlippage <= amount1 * 1e18,
            "UniswapV4Lib/amount1Max-too-high"
        );
    }

    function _validateLiquidityDecrease(
        CommonParams calldata commonParams,
        int24                 tickLower,
        int24                 tickUpper,
        uint128               liquidityDecrease,
        uint256               amount0Min,
        uint256               amount1Min
    ) internal view {
        _requireNonZeroMaxSlippage(commonParams);

        ( uint256 amount0, uint256 amount1 ) = getAmountsForLiquidity(
            commonParams.poolId,
            tickLower,
            tickUpper,
            liquidityDecrease
        );

        // Ensure the amountMin is above the allowed worst case scenario (amount * maxSlippage).
        require(
            amount0Min * 1e18 >= amount0 * commonParams.maxSlippage,
            "UniswapV4Lib/amount0Min-too-small"
        );

        require(
            amount1Min * 1e18 >= amount1 * commonParams.maxSlippage,
            "UniswapV4Lib/amount1Min-too-small"
        );
    }

    function _requireNonZeroMaxSlippage(CommonParams calldata commonParams) internal pure {
        require(commonParams.maxSlippage != 0, "UniswapV4Lib/maxSlippage-not-set");
    }
}
