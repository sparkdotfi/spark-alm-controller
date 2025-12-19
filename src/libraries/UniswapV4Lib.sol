// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Currency } from "../../lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";

import { IV4Router }    from "../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";
import { Actions }      from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { IERC20Like, IPermit2Like }                   from "../interfaces/Common.sol";
import { IALMProxy }                                  from "../interfaces/IALMProxy.sol";
import { IRateLimits }                                from "../interfaces/IRateLimits.sol";
import { IPositionManagerLike, IUniversalRouterLike } from "../interfaces/UniswapV4.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library UniswapV4Lib {

    struct TickLimits {
        int24  tickLowerMin;
        int24  tickUpperMax;
        uint24 maxTickSpacing;
    }

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");
    bytes32 public constant LIMIT_SWAP     = keccak256("LIMIT_UNISWAP_V4_SWAP");

    uint256 internal constant _V4_SWAP = 0x10;

    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments (Ethereum Mainnet).
    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function mintPosition(
        address proxy,
        address rateLimits,
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        mapping(bytes32 poolId => TickLimits tickLimits) storage tickLimits
    )
        external
    {
        _checkTickLimits(tickLimits[poolId], tickLower, tickUpper);

        PoolKey memory poolKey = getPoolKeyFromPoolId(poolId);

        bytes memory callData = _getMintCalldata({
            poolKey    : poolKey,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            proxy      : proxy
        });

        _increaseLiquidity({
            proxy      : proxy,
            rateLimits : rateLimits,
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });
    }

    function increasePosition(
        address proxy,
        address rateLimits,
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint256 amount0Max,
        uint256 amount1Max,
        mapping(bytes32 poolId => TickLimits tickLimits) storage tickLimits
    )
        external
    {
        // Must not increase liquidity on a position that is not owned by the ALMProxy.
        require(
            IPositionManagerLike(_POSITION_MANAGER).ownerOf(tokenId) == proxy,
            "MC/non-proxy-position"
        );

        ( PoolKey memory poolKey, PositionInfo info ) = _getPoolKeyAndPositionInfo(tokenId);

        _requirePoolIdMatch(poolId, poolKey);

        // Since funds are being added to the position, the ticks of the position need to be checked
        // since it's possible the position was transferred to the proxy, and its tick range may not
        // adhere to the constraints that would have been applied if it were minted by the proxy.
        _checkTickLimits(tickLimits[poolId], info.tickLower(), info.tickUpper());

        bytes memory callData = _getIncreaseLiquidityCallData({
            poolKey           : poolKey,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max
        });

        _increaseLiquidity({
            proxy      : proxy,
            rateLimits : rateLimits,
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            callData   : callData
        });
    }

    function decreasePosition(
        address proxy,
        address rateLimits,
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
    {
        PoolKey memory poolKey = getPoolKeyFromTokenId(tokenId);

        // NOTE: No need to check the token ownership here, as the proxy will be defined as the
        //       recipient of the tokens, so the worst case is that another account's position is
        //       decreased or closed by the proxy.
        _requirePoolIdMatch(poolId, poolKey);

        bytes memory callData = _getDecreaseLiquidityCallData({
            proxy             : proxy,
            poolKey           : poolKey,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });

        _decreaseLiquidity({
            proxy      : proxy,
            rateLimits : rateLimits,
            poolId     : poolId,
            token0     : Currency.unwrap(poolKey.currency0),
            token1     : Currency.unwrap(poolKey.currency1),
            amount0Min : amount0Min,
            amount1Min : amount1Min,
            callData   : callData
        });
    }

    function swap(
        address proxy,
        address rateLimits,
        bytes32 poolId,
        address tokenIn,
        uint128 amountIn,
        uint128 amountOutMin,
        uint256 maxSlippage
    )
        external
    {
        require(maxSlippage != 0, "MC/max-slippage-not-set");

        PoolKey memory poolKey = getPoolKeyFromPoolId(poolId);

        require(
            tokenIn == Currency.unwrap(poolKey.currency0) ||
            tokenIn == Currency.unwrap(poolKey.currency1),
            "MC/invalid-tokenIn"
        );

        // Perform rate limit decrease.
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(LIMIT_SWAP, poolId),
            _getNormalizedBalance(tokenIn, amountIn)
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bool zeroForOne = tokenIn == Currency.unwrap(poolKey.currency0);

        address tokenOut = zeroForOne
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);

        require(
            _getNormalizedBalance(tokenOut, amountOutMin) * 1e18 >=
            _getNormalizedBalance(tokenIn, amountIn) * maxSlippage,
            "MC/amountOutMin-too-low"
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey          : poolKey,
                zeroForOne       : zeroForOne,
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

        _approveWithPermit2(proxy, tokenIn, _ROUTER, amountIn);

        // Perform action.
        IALMProxy(proxy).doCall(
            _ROUTER,
            abi.encodeCall(
                IUniversalRouterLike.execute,
                (abi.encodePacked(uint8(_V4_SWAP)), inputs, block.timestamp)
            )
        );

        // Reset approval of Permit2 in tokenIn.
        _approveWithPermit2(proxy, tokenIn, _ROUTER, 0);
    }

    function getPoolKeyFromPoolId(bytes32 poolId) public view returns (PoolKey memory poolKey) {
        return IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approveWithPermit2(
        address proxy,
        address token,
        address spender,
        uint256 amount
    )
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
                (token, abi.encodeCall(IERC20Like.approve, (_PERMIT2, 0)))
            )
        );

        if (amount != 0) {
            // Approve the Permit2 contract to spend the amount of token (success is mandatory).
            bytes memory approveResult = IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC20Like.approve, (_PERMIT2, amount))
            );

            // Revert if approve returns anything, and that anything is not `true`.
            require(
                approveResult.length == 0 || abi.decode(approveResult, (bool)),
                "MC/permit2-approve-failed"
            );
        }

        // Finally, approve the Position Manager contract to spend the token via Permit2.
        IALMProxy(proxy).doCall(
            _PERMIT2,
            abi.encodeCall(
                IPermit2Like.approve,
                (token, spender, uint160(amount), uint48(block.timestamp))
            )
        );
    }

    function _increaseLiquidity(
        address        proxy,
        address        rateLimits,
        bytes32        poolId,
        address        token0,
        address        token1,
        uint256        amount0Max,
        uint256        amount1Max,
        bytes   memory callData
    )
        internal
    {
        _approveWithPermit2(proxy, token0, _POSITION_MANAGER, amount0Max);
        _approveWithPermit2(proxy, token1, _POSITION_MANAGER, amount1Max);

        // Get token balances before liquidity increase.
        uint256 startingBalance0 = _getBalance(token0, proxy);
        uint256 startingBalance1 = _getBalance(token1, proxy);

        // Perform action
        IALMProxy(proxy).doCall(_POSITION_MANAGER, callData);

        // Get token balances after liquidity increase.
        uint256 endingBalance0 = _getBalance(token0, proxy);
        uint256 endingBalance1 = _getBalance(token1, proxy);

        // Account for the theoretical possibility of receiving tokens when adding liquidity by
        // using a clamped subtraction.
        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.00000 USDC = 1.000000000000000000 USDS).
        uint256 rateLimitDecrease = _clampedSub(
            _getNormalizedBalance(token0, startingBalance0) +
            _getNormalizedBalance(token1, startingBalance1),
            _getNormalizedBalance(token0, endingBalance0) +
            _getNormalizedBalance(token1, endingBalance1)
        );

        // Perform rate limit decrease.
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(LIMIT_DEPOSIT, poolId),
            rateLimitDecrease
        );

        // Reset approval of Permit2 in token0 and token1
        // NOTE: It's not necessary to reset the Position Manager approval in Permit2 (as it
        //       doesn't have allowance in the token at this point), but prudent so there isn't a
        //       hanging unused approval.
        _approveWithPermit2(proxy, token0, _POSITION_MANAGER, 0);
        _approveWithPermit2(proxy, token1, _POSITION_MANAGER, 0);
    }

    function _decreaseLiquidity(
        address        proxy,
        address        rateLimits,
        bytes32        poolId,
        address        token0,
        address        token1,
        uint256        amount0Min,
        uint256        amount1Min,
        bytes   memory callData
    )
        internal
    {
        // Get token balances before liquidity decrease.
        uint256 startingBalance0 = _getBalance(token0, proxy);
        uint256 startingBalance1 = _getBalance(token1, proxy);

        // Perform action.
        IALMProxy(proxy).doCall(_POSITION_MANAGER, callData);

        // Get token balances after liquidity decrease.
        uint256 endingBalance0 = _getBalance(token0, proxy);
        uint256 endingBalance1 = _getBalance(token1, proxy);

        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.00000 USDC = 1.000000000000000000 USDS).
        uint256 rateLimitDecrease =
            _getNormalizedBalance(token0, endingBalance0 - startingBalance0) +
            _getNormalizedBalance(token1, endingBalance1 - startingBalance1);

        // Perform rate limit decrease.
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(LIMIT_WITHDRAW, poolId),
            rateLimitDecrease
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _checkTickLimits(TickLimits memory limits, int24 tickLower, int24 tickUpper)
        internal pure
    {
        require(limits.maxTickSpacing != 0,       "MC/tickLimits-not-set");
        require(tickLower < tickUpper,            "MC/ticks-misordered");
        require(tickLower >= limits.tickLowerMin, "MC/tickLower-too-low");
        require(tickUpper <= limits.tickUpperMax, "MC/tickUpper-too-high");

        require(
            uint256(int256(tickUpper) - int256(tickLower)) <= limits.maxTickSpacing,
            "MC/tickSpacing-too-wide"
        );
    }

    function _clampedSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        return a > b ? a - b : 0;
    }

    function _getBalance(address token, address account) internal view returns (uint256 balance) {
        return IERC20Like(token).balanceOf(account);
    }

    function _getMintCalldata(
        address        proxy,
        PoolKey memory poolKey,
        int24          tickLower,
        int24          tickUpper,
        uint128        liquidity,
        uint256        amount0Max,
        uint256        amount1Max
    )
        internal view returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            poolKey,     // Which pool to mint in
            tickLower,   // Position's lower price bound
            tickUpper,   // Position's upper price bound
            liquidity,   // Amount of liquidity to mint
            amount0Max,  // Maximum amount of token0 to use
            amount1Max,  // Maximum amount of token1 to use
            proxy,       // NFT recipient
            ""           // No hook data needed
        );

        params[1] = abi.encode(
            poolKey.currency0,  // First token to settle
            poolKey.currency1   // Second token to settle
        );

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getIncreaseLiquidityCallData(
        PoolKey memory poolKey,
        uint256        tokenId,
        uint128        liquidityIncrease,
        uint256        amount0Max,
        uint256        amount1Max
    )
        internal view returns (bytes memory callData)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            tokenId,            // Position to increase
            liquidityIncrease,  // Amount to add
            amount0Max,         // Maximum token0 to spend
            amount1Max,         // Maximum token1 to spend
            ""                  // No hook data needed
        );

        params[1] = abi.encode(poolKey.currency0);
        params[2] = abi.encode(poolKey.currency1);

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getDecreaseLiquidityCallData(
        address        proxy,
        PoolKey memory poolKey,
        uint256        tokenId,
        uint128        liquidityDecrease,
        uint256        amount0Min,
        uint256        amount1Min
    )
        internal view returns (bytes memory callData)
    {
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
            proxy               // Who receives the tokens
        );

        return _getModifyLiquiditiesCallData(actions, params);
    }

    function _getModifyLiquiditiesCallData(bytes memory actions, bytes[] memory params)
        internal view returns (bytes memory callData)
    {
        return abi.encodeCall(
            IPositionManagerLike.modifyLiquidities,
            (abi.encode(actions, params), block.timestamp)
        );
    }

    function _getNormalizedBalance(address token, uint256 balance)
        internal view returns (uint256 normalizedBalance)
    {
        return balance * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _getPoolKeyAndPositionInfo(uint256 tokenId)
        internal view returns (PoolKey memory poolKey, PositionInfo info)
    {
        return IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);
    }

    function getPoolKeyFromTokenId(uint256 tokenId)
        public view returns (PoolKey memory poolKey)
    {
        (poolKey, ) = _getPoolKeyAndPositionInfo(tokenId);
    }

    function _requirePoolIdMatch(bytes32 poolId, PoolKey memory poolKey) internal pure {
        require(keccak256(abi.encode(poolKey)) == poolId, "MC/tokenId-poolId-mismatch");
    }

}
