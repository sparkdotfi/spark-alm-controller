// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IAsyncRedeemManagerLike {

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

    function issuedShares(uint64 poolId, bytes16 scId, uint128 shareAmount, uint128 pricePoolPerShare) external;

    function revokedShares(
        uint64  poolId,
        bytes16 scId,
        uint128 assetId,
        uint128 assetAmount,
        uint128 shareAmount,
        uint128 pricePoolPerShare
    ) external;

    function balanceSheet() external view returns (address);

    function globalEscrow() external view returns (address);

    function poolEscrow(uint64 poolId) external view returns (address);

    function spoke() external view returns (address);

}

interface ICentrifugeV3VaultLike {

    function asset() external view returns (address);

    function manager() external view returns (address);

    function poolId() external view returns (uint64);

    function root() external view returns (address);

    function scId() external view returns (bytes16);

    function share() external view returns (address);

    function pendingCancelDepositRequest(uint256 requestId, address controller)
        external view returns (bool isPending);

    function pendingCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (bool isPending);

    function pendingDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingAssets);

    function pendingRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingShares);

    function claimableCancelDepositRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableAssets);

    function claimableCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableShares);

    function claimableDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableAssets);

    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);
}

interface ISpokeLike {

    event InitiateTransferShares(
        uint16          centrifugeId,
        uint64  indexed poolId,
        bytes16 indexed scId,
        address indexed sender,
        bytes32         destinationAddress,
        uint128         amount
    );

    function assetToId(address asset, uint256 tokenId) external view returns (uint128);

    function updatePricePoolPerShare(uint64 poolId, bytes16 scId, uint128 price, uint64 computedAt) external;

    function updatePricePoolPerAsset(
        uint64  poolId,
        bytes16 scId,
        uint128 assetId,
        uint128 poolPerAsset,
        uint64  computedAt
    ) external;

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256 balance);

    function totalSupply() external view returns (uint256 totalSupply);

}

interface IERC20MintableLike is IERC20Like {

    function mint(address to, uint256 amount) external;

}

interface ICentrifugeV3ShareLike is IERC20MintableLike {

    function mint(address to, uint256 value) external;

    function hook() external view returns (address);

}

interface IFreelyTransferableHookLike {

    function updateMember(address token, address user, uint64 validUntil) external;

}

interface IBalanceSheetLike {

    function deposit(uint64 poolId, bytes16 scId, address asset, uint256 tokenId, uint128 amount)
        external;

}

interface IRestrictionManager {

    function updateMember(address token, address user, uint64 validUntil) external;

}

interface IInvestmentManager {

    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;

    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares
    ) external;

    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

}
