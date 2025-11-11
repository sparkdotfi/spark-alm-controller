// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Currency } from "../../lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";

import { Actions } from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";

import { IERC20Like, IPermit2Like } from "../interfaces/Common.sol";
import { IALMProxy }                from "../interfaces/IALMProxy.sol";
import { IRateLimits }              from "../interfaces/IRateLimits.sol";
import { IPositionManagerLike }     from "../interfaces/UniswapV4.sol";

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
        // Encode actions and params
        PoolKey memory poolKey = _getPoolKey(commonParams.poolId);

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
            "MC/non-proxy-position"
        );

        _requirePoolIdMatch(commonParams.poolId, tokenId);

        PoolKey memory poolKey = _getPoolKey(commonParams.poolId);

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
        _requirePoolIdMatch(commonParams.poolId, tokenId);

        PoolKey memory poolKey = _getPoolKey(commonParams.poolId);

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
            amount0Min   : amount0Min,
            amount1Min   : amount1Min,
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
        _requirePoolIdMatch(commonParams.poolId, tokenId);

        PoolKey memory poolKey = _getPoolKey(commonParams.poolId);

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
            amount0Min   : amount0Min,
            amount1Min   : amount1Min,
            actions      : actions,
            params       : params
        });
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _approvePositionManager(address proxy, address token, uint256 amount) internal {
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
        _requireNonZeroMaxSlippage(commonParams);

        _approvePositionManager(commonParams.proxy, token0, amount0Max);
        _approvePositionManager(commonParams.proxy, token1, amount1Max);

        // Get token balances before mint.
        uint256 startingBalance0 = _getBalance(token0, commonParams.proxy);
        uint256 startingBalance1 = _getBalance(token1, commonParams.proxy);

        // Perform action
        IALMProxy(commonParams.proxy).doCall(
            _POSITION_MANAGER,
            abi.encodeCall(
                IPositionManagerLike.modifyLiquidities,
                (abi.encode(actions, params), block.timestamp)
            )
        );

        // Get token balances after mint.
        uint256 endingBalance0 = _getBalance(token0, commonParams.proxy);
        uint256 endingBalance1 = _getBalance(token1, commonParams.proxy);

        // Ensure the amountMax is below the allowed worst case scenario (amount / maxSlippage).
        require(
            amount0Max * commonParams.maxSlippage <=
            _clampedSub(startingBalance0, endingBalance0) * 1e18,
            "MC/amount0Max-too-high"
        );

        require(
            amount1Max * commonParams.maxSlippage <=
            _clampedSub(startingBalance1, endingBalance1) * 1e18,
            "MC/amount1Max-too-high"
        );

        // Account for the theoretical possibility of receiving tokens when adding liquidity by
        // using a clamped subtraction.
        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.00000 USDC = 1.000000000000000000 USDS).
        rateLimitDecrease = _clampedSub(
            _getNormalizedBalance(token0, startingBalance0) +
            _getNormalizedBalance(token1, startingBalance1),
            _getNormalizedBalance(token0, endingBalance0) +
            _getNormalizedBalance(token1, endingBalance1)
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
        uint256               amount0Min,
        uint256               amount1Min,
        bytes        memory   actions,
        bytes[]      memory   params
    ) internal returns (uint256 rateLimitDecrease) {
        _requireNonZeroMaxSlippage(commonParams);

        // Get token balances before mint.
        uint256 startingBalance0 = _getBalance(token0, commonParams.proxy);
        uint256 startingBalance1 = _getBalance(token1, commonParams.proxy);

        // Perform action
        IALMProxy(commonParams.proxy).doCall(
            _POSITION_MANAGER,
            abi.encodeCall(
                IPositionManagerLike.modifyLiquidities,
                (abi.encode(actions, params), block.timestamp)
            )
        );

        // Get token balances after mint.
        uint256 endingBalance0 = _getBalance(token0, commonParams.proxy);
        uint256 endingBalance1 = _getBalance(token1, commonParams.proxy);

        // Ensure the amountMin is above the allowed worst case scenario (amount * maxSlippage).
        require(
            amount0Min * 1e18 >= (endingBalance0 - startingBalance0) * commonParams.maxSlippage,
            "MC/amount0Min-too-small"
        );

        require(
            amount1Min * 1e18 >= (endingBalance1 - startingBalance1) * commonParams.maxSlippage,
            "MC/amount1Min-too-small"
        );

        // NOTE: The limitation of this integration is the assumption that the tokens are valued
        //       equally (i.e. 1.00000 USDC = 1.000000000000000000 USDS).
        rateLimitDecrease =
            _getNormalizedBalance(token0, endingBalance0) +
            _getNormalizedBalance(token1, endingBalance1) -
            _getNormalizedBalance(token0, startingBalance0) -
            _getNormalizedBalance(token1, startingBalance1);

        // Perform rate limit decrease.
        IRateLimits(commonParams.rateLimits).triggerRateLimitDecrease(
            RateLimitHelpers.makeBytes32Key(commonParams.rateLimitId, commonParams.poolId),
            rateLimitDecrease
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _clampedSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        return a > b ? a - b : 0;
    }

    function _getBalance(address token, address account ) internal view returns (uint256 balance) {
        return IERC20Like(token).balanceOf(account);
    }

    function _getNormalizedBalance(
        address token,
        uint256 balance
    ) internal view returns (uint256 normalizedBalance) {
        return balance * 1e18 / (10 ** IERC20Like(token).decimals());
    }

    function _getPoolKey(bytes32 poolId) internal view returns (PoolKey memory poolKey) {
        return IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(poolId));
    }

    function _requireNonZeroMaxSlippage(CommonParams calldata commonParams) internal pure {
        require(commonParams.maxSlippage != 0, "MC/maxSlippage-not-set");
    }

    function _requirePoolIdMatch(bytes32 poolId, uint256 tokenId) internal view {
        ( PoolKey memory poolKey, ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        require(keccak256(abi.encode(poolKey)) == poolId, "MC/tokenId-poolId-mismatch");
    }
}
