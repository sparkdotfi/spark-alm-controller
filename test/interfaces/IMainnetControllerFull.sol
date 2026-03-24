// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IController } from "../../src/interfaces/IController.sol";

import { MainnetController } from "../../src/MainnetController.sol";

abstract contract IMainnetControllerFull is IController, MainnetController {

    /**********************************************************************************************/
    /*** DaiUsdsFacet actions                                                                   ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external virtual;

    function swapDAIToUSDS(uint256 daiAmount) external virtual;

    /**********************************************************************************************/
    /*** TransferAssetFacet actions                                                             ***/
    /**********************************************************************************************/

    function LIMIT_ASSET_TRANSFER() external pure virtual returns (bytes32);

    function transferAsset(address asset, address destination, uint256 amount) external virtual;

}
