// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

interface ICentrifugeV3VaultLike is IERC7540 {
    function asset()   external view returns (address);
    function share()   external view returns (address);
    function manager() external view returns (address);
    function poolId()  external view returns (uint64);
    function scId()    external view returns (bytes16);
    function root()    external view returns (address);

    function claimableCancelDepositRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableAssets);
    function claimableCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableShares);
    function pendingCancelDepositRequest(uint256 requestId, address controller)
        external view returns (bool isPending);
    function pendingCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (bool isPending);

    function cancelDepositRequest(uint256 requestId, address controller) external;
    function cancelRedeemRequest(uint256 requestId, address controller) external;
    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external returns (uint256 assets);
    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external returns (uint256 shares);
}

interface IAsyncRedeemManagerLike {
    function issuedShares(
        uint64  poolId,
        bytes16 scId,
        uint128 shareAmount,
        uint128 pricePoolPerShare) external;
    function revokedShares(
        uint64  poolId,
        bytes16 scId,
        uint128 assetId,
        uint128 assetAmount,
        uint128 shareAmount,
        uint128 pricePoolPerShare) external;
    function approvedDeposits(
        uint64  poolId,
        bytes16 scId,
        uint128 assetId,
        uint128 assetAmount,
        uint128 pricePoolPerAsset
    ) external;
    function fulfillDepositRequest(
        uint64  poolId,
        bytes16 scId,
        address user,
        uint128 assetId,
        uint128 fulfilledAssets,
        uint128 fulfilledShares,
        uint128 cancelledAssets
    ) external;
    function fulfillRedeemRequest(
        uint64  poolId,
        bytes16 scId,
        address user,
        uint128 assetId,
        uint128 fulfilledAssets,
        uint128 fulfilledShares,
        uint128 cancelledShares
    ) external;
    function balanceSheet()            external view returns (address);
    function spoke()                   external view returns (address);
    function poolEscrow(uint64 poolId) external view returns (address);
    function globalEscrow()            external view returns (address);
}

interface ISpokeLike {
    function assetToId(address asset, uint256 tokenId) external view returns (uint128);
    function updatePricePoolPerShare(uint64 poolId, bytes16 scId, uint128 price, uint64 computedAt) external;
    function updatePricePoolPerAsset(uint64 poolId, bytes16 scId, uint128 assetId, uint128 poolPerAsset_, uint64 computedAt) external; // Use when price is not available
    function crosschainTransferShares(
        uint16 centrifugeId,
        uint64 poolId,
        bytes16 scId,
        bytes32 receiver,
        uint128 amount,
        uint128 remoteExtraGasLimit
    ) external payable;
}
