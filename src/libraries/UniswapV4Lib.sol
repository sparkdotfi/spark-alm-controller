// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { Currency }     from "v4-core/types/Currency.sol";
import { IHooks }       from "v4-core/interfaces/IHooks.sol";
// import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
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

struct UniV4AddLiquidityParams {
    IALMProxy proxy;
    IRateLimits rateLimits;
    bytes32 rateLimitId;
    uint256 maxSlippage;
    bytes32 poolId;    // the PoolId of the Uniswap V4 pool
    int24   tickLower;
    int24   tickUpper;
    uint128 liquidity;   // amount of liquidity units to mint
    uint256 amount0Max;  // maximum amount of currency0 caller is willing to pay
    uint256 amount1Max;  // maximum amount of currency1 caller is willing to pay
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
    // IPoolManager     public poolm      = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IPositionManager public constant posm       = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    IStateView       public constant stateView  = IStateView(0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227);
    IPermit2         public constant permit2    = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function mintPositionUniV4(UniV4AddLiquidityParams memory ps /* params */) external {
        // NOTE: Returning values is not possible because PositionManager.modifyLiquidities does not
        // return anything. Callers that want to know eg how much was used can read balances before
        // and after.
        _addLiquidityUniV4(ps, true);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _addLiquidityUniV4(UniV4AddLiquidityParams memory ps /* params */, bool mint) internal {
        // PositionManager stores poolKeys as bytes25
        PoolKey memory poolKey = HasPoolKeys(address(posm)).poolKeys(bytes25(ps.poolId));

        // Perform rate limit
        ps.rateLimits.triggerRateLimitDecrease(
            keccak256(abi.encode(ps.rateLimitId, ps.poolId)),
            ps.liquidity
        );

        // Perform maxSlippages / amount0Max & amount1Max checks
        require(ps.maxSlippage != 0, "UniswapV4Lib: maxSlippage not set");

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(PoolId.wrap(ps.poolId));
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(ps.tickLower),
            TickMath.getSqrtPriceAtTick(ps.tickUpper),
            ps.liquidity
        );

        // NOTE: The - 1 is to avoid rounding issues: If the entire tick range lies outside of the
        // current price, one of {amount0Max, amount1Max} will be 0. However, it is conceivable that
        // callers will add 1 to amount0Max and amount1Max to account for the potential for rounding
        // errors. To allow for that behavior, we subtract 1 here.
        require(
            ps.amount0Max - 1 <= amount0 * 1e18 / ps.maxSlippage,
            "UniswapV4Lib: amount0Max too high"
        );
        require(
            ps.amount1Max - 1 <= amount1 * 1e18 / ps.maxSlippage,
            "UniswapV4Lib: amount1Max too high"
        );

        // Encode actions and params
        bytes   memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params  = new bytes[](2);

        params[0] = abi.encode(
            poolKey, ps.tickLower, ps.tickUpper, ps.liquidity, ps.amount0Max, ps.amount1Max, ps.proxy, ""
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        // Submit Calls
        _approvePermit2andPosm(ps.proxy, poolKey.currency0, ps.amount0Max);
        _approvePermit2andPosm(ps.proxy, poolKey.currency1, ps.amount1Max);

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

