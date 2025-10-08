// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { PoolId }  from "../../lib/uniswap-v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";

import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

interface IPositionManagerLike {

    function getPoolAndPositionInfo(
        uint256 tokenId
    ) external view returns (PoolKey memory poolKey, PositionInfo info);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory poolKeys);

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    function ownerOf(uint256 tokenId) external view returns (address owner);

}

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}
