// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IController } from "../../src/interfaces/IController.sol";

import { ForeignController } from "../../src/ForeignController.sol";

abstract contract IForeignControllerFull is IController, ForeignController {

    /**********************************************************************************************/
    /*** PSM3Facet actions                                                                     ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount) external virtual returns (uint256 shares);

    function withdrawPSM(address asset, uint256 maxAmount) external virtual returns (uint256 assetsWithdrawn);

    function LIMIT_PSM_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_PSM_WITHDRAW() external pure virtual returns (bytes32);

    /**********************************************************************************************/
    /*** ERC7540Facet actions                                                                   ***/
    /**********************************************************************************************/

    function claimDepositERC7540(address token) external virtual;

    function claimRedeemERC7540(address token) external virtual;

    function requestDepositERC7540(address token, uint256 amount) external virtual;

    function requestRedeemERC7540(address token, uint256 shares) external virtual;

    function LIMIT_7540_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_7540_REDEEM() external pure virtual returns (bytes32);

    /**********************************************************************************************/
    /*** SparkVaultFacet actions                                                                ***/
    /**********************************************************************************************/

    function LIMIT_SPARK_VAULT_TAKE() external pure virtual returns (bytes32);

    function takeFromSparkVault(address sparkVault, uint256 assetAmount) external virtual;

    /**********************************************************************************************/
    /*** TransferAssetFacet actions                                                             ***/
    /**********************************************************************************************/

    function LIMIT_ASSET_TRANSFER() external pure virtual returns (bytes32);

    function transferAsset(address asset, address destination, uint256 amount) external virtual;

}
