// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Id, MarketParams } from "../../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

}

interface IERC20MetadataLike {

    function symbol() external view returns (string memory);

}

interface IERC4626Like is IERC20MetadataLike, IERC20Like {

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

interface IMetaMorphoLike is IERC4626Like {

    function acceptCap(MarketParams memory marketParams) external;

    function setCurator(address newCurator) external;

    function setFeeRecipient(address newFeeRecipient) external;

    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    function setSkimRecipient(address newSkimRecipient) external;

    function setSupplyQueue(Id[] calldata newSupplyQueue) external;

    function submitCap(MarketParams memory marketParams, uint256 newSupplyCap) external;

    function submitGuardian(address newGuardian) external;

    function curator() external view returns (address);

    function feeRecipient() external view returns (address);

    function guardian() external view returns (address);

    function isAllocator(address target) external view returns (bool);

    function MORPHO() external view returns (address);

    function timelock() external view returns (uint256);

}

interface IMorphoLike {

    function createMarket(MarketParams memory marketParams) external;

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    function market(Id id) external view returns (Market memory m);

}
