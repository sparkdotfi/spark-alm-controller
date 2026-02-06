// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

}

interface IERC4626Like is IERC20Like{

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IMapleTokenLike is IERC4626Like {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

}

interface IMapleTokenExtendedLike is IMapleTokenLike {

    function manager() external view returns (address);

}

interface IPermissionManagerLike {

    function admin() external view returns (address);

    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;

}

interface IPoolManagerLike {

    function withdrawalManager() external view returns (address);

    function poolDelegate() external view returns (address);

}

interface IWithdrawalManagerLike {

    function processRedemptions(uint256 maxSharesToProcess) external;

}
