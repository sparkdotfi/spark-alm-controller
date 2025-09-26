// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { Currency }     from "v4-core/types/Currency.sol";
import { IHooks }       from "v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { PoolId }       from "v4-core/types/PoolId.sol";
import { PoolKey }      from "v4-core/types/PoolKey.sol";
import { TickMath }     from "v4-core/libraries/TickMath.sol";

import { Actions }          from "v4-periphery/src/libraries/Actions.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { IStateView }       from "v4-periphery/src/interfaces/IStateView.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

import { LiquidityAmounts } from "../vendor/LiquidityAmounts.sol";

interface HasPoolKeys {
    function poolKeys(bytes25 poolId) external view returns (PoolKey memory);
}


/**********************************************************************************************/
/*** Structs                                                                                ***/
/**********************************************************************************************/

struct UniV4Params {
    IALMProxy   proxy;
    IRateLimits rateLimits;
    bytes32     rateLimitId;
    uint256     maxSlippage;
    bytes32     poolId;  // the PoolId of the Uniswap V4 pool
}

library UniswapV4Lib {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/
    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments:
    // Mainnet Deployments
    // Ethereum: 1
    // Contract	Address
    // PoolManager	0x000000000004444c5dc75cB358380D2e3dE08A90
    // PositionDescriptor	0xd1428ba554f4c8450b763a0b2040a4935c63f06c
    // PositionManager	0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e
    // Quoter	0x52f0e24d1c21c8a0cb1e5a5dd6198556bd9e1203
    // StateView	0x7ffe42c4a5deea5b0fec41c94c136cf115597227
    // Universal Router	0x66a9893cc07d91d95644aedd05d03f95e1dba8af
    // Permit2	0x000000000022D473030F116dDEE9F6B43aC78BA3
    // IPoolManager     public constant poolm      = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager public constant posm       = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    IStateView       public constant stateView  = IStateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IPermit2         public constant permit2    = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function mintPosition(
        UniV4Params calldata ps /* params */,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidityInitial,
        uint256 amount0Max,
        uint256 amount1Max
    ) external {
        // NOTE: Returning values is not possible because PositionManager.modifyLiquidities does not
        // return anything. Callers that want to know eg how much was used can read balances before
        // and after.

        // Encode actions and params
        bytes   memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params  = new bytes[](2);

        // From the documentation:
        // ```
        //     // Parameters for MINT_POSITION
        //     params[0] = abi.encode(
        //         poolKey,     // Which pool to mint in
        //         tickLower,   // Position's lower price bound
        //         tickUpper,   // Position's upper price bound
        //         liquidity,   // Amount of liquidity to mint
        //         amount0Max,  // Maximum amount of token0 to use
        //         amount1Max,  // Maximum amount of token1 to use
        //         recipient,   // Who receives the NFT
        //         ""           // No hook data needed
        //     );
        // ```
        PoolKey memory poolKey = HasPoolKeys(address(posm)).poolKeys(bytes25(ps.poolId));

        params[0] = abi.encode(
            poolKey, tickLower, tickUpper, liquidityInitial, amount0Max, amount1Max, ps.proxy, ""
        );

        // ```
        //    // Parameters for SETTLE_PAIR - specify tokens to provide
        //    params[1] = abi.encode(
        //        poolKey.currency0,  // First token to settle
        //        poolKey.currency1   // Second token to settle
        //    );
        // ```
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        _mintOrIncrease(
            ps,
            tickLower,
            tickUpper,
            liquidityInitial,
            amount0Max,
            amount1Max,
            actions,
            params
        );
    }

    function addLiquidity(
        UniV4Params memory ps /* params */,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint256 amount0Max,
        uint256 amount1Max
    ) external {
        _ensureTokenIdForPoolId(tokenId, ps.poolId);

        // When adding liquidity, accrued fees are automatically accounted. Thus it is
        // technically possible that the delta will be in favor of the liquidity provider. Since
        // settle pair always assumes an obligation from the provider to the pool, we use close
        // currency instead, which doesn't have this requirement (btw, take pair does the exact
        // opposite (it assumes the obligation is from the pool to the provider)).
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);

        // ```
        //    // Parameters for INCREASE_LIQUIDITY
        //    params[0] = abi.encode(
        //        tokenId,           // Position to increase
        //        liquidityIncrease, // Amount to add
        //        amount0Max,        // Maximum token0 to spend
        //        amount1Max,        // Maximum token1 to spend
        //        ""                // No hook data needed
        //    );
        // ```
        params[0] = abi.encode(tokenId, liquidityIncrease, amount0Max, amount1Max, "");

        // ```
        //    // CLOSE_CURRENCY only needs the currency
        //    params[1] = abi.encode(currency0);
        // ```
        PoolKey memory poolKey = HasPoolKeys(address(posm)).poolKeys(bytes25(ps.poolId));

        params[1] = abi.encode(poolKey.currency0);
        params[2] = abi.encode(poolKey.currency1);
    }

    function burnPosition(
        UniV4Params memory ps /* params */,
        uint256 tokenId,
        uint256 amount0Min,
        uint256 amount1Min
    ) external {
        uint128 liquidityCurrent = stateView.getPositionLiquidity(
            { poolId: PoolId.wrap(ps.poolId), positionId: bytes32(tokenId) }
        );

        _ensureTokenIdForPoolId(tokenId, ps.poolId);

        // Perform rate limit
        ps.rateLimits.triggerRateLimitIncrease(
            keccak256(abi.encode(ps.rateLimitId, ps.poolId)),
            liquidityCurrent
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.BURN_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );
        bytes[] memory params = new bytes[](2);

        // ```
        //    // Parameters for BURN_POSITION
        //    params[0] = abi.encode(
        //        tokenId,     // Position to burn
        //        amount0Min,  // Minimum token0 to receive
        //        amount1Min,  // Minimum token1 to receive
        //        ""           // No hook data needed
        //    );
        // ```
        params[0] = abi.encode(tokenId, amount0Min, amount1Min, "");

        // ```
        //    // Parameters for SETTLE_PAIR - specify tokens to provide
        //    params[1] = abi.encode(
        //        poolKey.currency0,  // First token to settle
        //        poolKey.currency1   // Second token to settle
        //    );
        // ```
        // params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        //
    }

    function decreaseLiquidity(
        UniV4Params memory ps /* params */,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min
    ) external {
        _ensureTokenIdForPoolId(tokenId, ps.poolId);

        // Perform rate limit
        ps.rateLimits.triggerRateLimitIncrease(
            keccak256(abi.encode(ps.rateLimitId, ps.poolId)),
            liquidityDecrease
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.SETTLE_PAIR)
        );
        bytes[] memory params = new bytes[](2);

        // ```
        //    // Parameters for DECREASE_LIQUIDITY
        //    params[0] = abi.encode(
        //        tokenId,           // Position to decrease
        //        liquidityDecrease, // Amount to remove
        //        amount0Min,       // Minimum token0 to receive
        //        amount1Min,       // Minimum token1 to receive
        //        ""                // No hook data needed
        //    );
        // ```
        params[0] = abi.encode(tokenId, liquidityDecrease, amount0Min, amount1Min, "");

        // ```
        //    // Parameters for SETTLE_PAIR - specify tokens to provide
        //    params[1] = abi.encode(
        //        poolKey.currency0,  // First token to settle
        //        poolKey.currency1   // Second token to settle
        //    );
        // ```
        // params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        //
        // // Submit Calls
        // ps.proxy.doCall(
        //     address(posm),
        //     abi.encodeCall(IPositionManager.modifyLiquidities, (abi.encode(actions, params), block.timestamp))
        // );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _ensureTokenIdForPoolId(uint256 tokenId, bytes32 poolId) internal view {
        // Ensure tokenId is for this pool
        // Yes, this generally available in the outer scope but code is clearer this way
        (PoolKey memory poolKey,) = posm.getPoolAndPositionInfo(tokenId);
        require(keccak256(abi.encode(poolKey)) == poolId, "UniswapV4Lib: tokenId poolId mismatch");
    }

    function _mintOrIncrease(
        UniV4Params memory ps /* params */,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        bytes memory actions,
        bytes[] memory params
    ) internal {
        // PositionManager stores poolKeys as bytes25
        PoolKey memory poolKey = HasPoolKeys(address(posm)).poolKeys(bytes25(ps.poolId));

        // Perform rate limit
        ps.rateLimits.triggerRateLimitDecrease(
            keccak256(abi.encode(ps.rateLimitId, ps.poolId)),
            liquidity
        );

        // Perform maxSlippages / amount0Max & amount1Max checks
        require(ps.maxSlippage != 0, "UniswapV4Lib: maxSlippage not set");

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(PoolId.wrap(ps.poolId));
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        // NOTE: The - 1 is to avoid rounding issues: If the entire tick range lies outside of the
        // current price, one of {amount0Max, amount1Max} will be 0. However, it is conceivable that
        // callers will add 1 to amount0Max and amount1Max to account for the potential for rounding
        // errors. To allow for that behavior, we subtract 1 here.
        require(
            amount0Max - 1 <= amount0 * 1e18 / ps.maxSlippage,
            "UniswapV4Lib: amount0Max too high"
        );
        require(
            amount1Max - 1 <= amount1 * 1e18 / ps.maxSlippage,
            "UniswapV4Lib: amount1Max too high"
        );

        // Submit Calls
        _approvePermit2andPosm(ps.proxy, poolKey.currency0, amount0Max);
        _approvePermit2andPosm(ps.proxy, poolKey.currency1, amount1Max);

        // Perform action
        ps.proxy.doCall(
            address(posm),
            abi.encodeCall(IPositionManager.modifyLiquidities, (abi.encode(actions, params), block.timestamp))
        );

        // Reset approval of Permit2 in token0 and token1
        // NOTE: It's not necessary to reset the Position Manager approval in Permit2 (as it doesn't
        // have allowance in the token at this point), but for let's do it anyway so we don't have
        // a hanging unusable approval.
        _approvePermit2andPosm(ps.proxy, poolKey.currency0, 0);
        _approvePermit2andPosm(ps.proxy, poolKey.currency1, 0);
    }

    function _approvePermit2andPosm(IALMProxy proxy, Currency currency, uint256 amount) internal {
        address token = Currency.unwrap(currency);

        // First, approve Permit2 in the token
        _approve(proxy, token, address(posm), amount);

        // Then approve the Position Manager in Permit2
        proxy.doCall(
            address(permit2),
            abi.encodeCall(permit2.approve, (token, address(posm), uint160(amount), uint48(block.timestamp)))
        );
    }

    function _approve(
        IALMProxy proxy,
        address   token,
        address   spender,
        uint256   amount
    )
        internal
    {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token
        ( bool success, bytes memory data )
            = address(proxy).call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        bytes memory approveCallReturnData;

        if (success) {
            // Data is the ABI-encoding of the approve call bytes return data, need to
            // decode it first
            approveCallReturnData = abi.decode(data, (bytes));
            // Approve was successful if 1) no return value or 2) true return value
            if (approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool))) {
                return;
            }
        }

        // If call was unsuccessful, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));

        approveCallReturnData = proxy.doCall(token, approveData);

        // Revert if approve returns false
        require(
            approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool)),
            "UniswapV4Lib/approve-failed"
        );
    }

}

