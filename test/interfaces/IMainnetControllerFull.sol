// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController } from "../../src/interfaces/IController.sol";

import { MainnetController } from "../../src/MainnetController.sol";

abstract contract IMainnetControllerFull is IController, MainnetController {

    /**********************************************************************************************/
    /*** DaiUsdsFacet actions                                                                   ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external virtual;

    function swapDAIToUSDS(uint256 daiAmount) external virtual;

    /**********************************************************************************************/
    /*** ERC4626 actions                                                                        ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external
        virtual
        returns (uint256 shares);

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        virtual returns (uint256 assets);

    function setMaxExchangeRate(
        address token,
        uint256 shares,
        uint256 maxExpectedAssets
    )
        external
        virtual;

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external
        virtual
        returns (uint256 shares);

    function EXCHANGE_RATE_PRECISION() external pure virtual returns (uint256);

    function LIMIT_4626_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_4626_WITHDRAW() external pure virtual returns (bytes32);

    function maxExchangeRates(address token) external view virtual returns (uint256);

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
    /*** MapleFacet actions                                                                     ***/
    /**********************************************************************************************/

    function cancelMapleRedemption(address mapleToken, uint256 shares) external virtual;

    function requestMapleRedemption(address mapleToken, uint256 shares) external virtual;

    function LIMIT_MAPLE_REDEEM() external pure virtual returns (bytes32);

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
    
    /**********************************************************************************************/
    /*** USDS vault actions                                                                     ***/
    /**********************************************************************************************/

    function LIMIT_USDS_MINT() external pure virtual returns (bytes32);

    function mintUSDS(uint256 usdsAmount) external virtual;

    function burnUSDS(uint256 usdsAmount) external virtual;

    /**********************************************************************************************/
    /*** WrapProxyETH actions                                                             ***/
    /**********************************************************************************************/

    function wrapAllProxyETH() external virtual;

    /**********************************************************************************************/
    /*** Ethena (USDE) actions                                                                  ***/
    /**********************************************************************************************/

    function LIMIT_USDE_BURN() external virtual view returns (bytes32);

    function LIMIT_USDE_MINT() external virtual view returns (bytes32);

    function LIMIT_SUSDE_COOLDOWN() external virtual view returns (bytes32);

    function cooldownAssetsSUSDe(uint256 usdeAmount) external virtual returns (uint256 cooldownShares);

    function cooldownSharesSUSDe(uint256 susdeAmount) external virtual returns (uint256 cooldownAssets);

    function prepareUSDeMint(uint256 usdcAmount) external virtual;

    function prepareUSDeBurn(uint256 usdeAmount) external virtual;

    function removeDelegatedSigner(address delegatedSigner) external virtual;

    function setDelegatedSigner(address delegatedSigner) external virtual;

    function unstakeSUSDe() external virtual;

    /**********************************************************************************************/
    /*** WSTETH actions                                                                      1   ***/
    /**********************************************************************************************/

    function LIMIT_WSTETH_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_WSTETH_REQUEST_WITHDRAW() external pure virtual returns (bytes32);

    function depositToWstETH(uint256 amount) external virtual;

    function claimWithdrawalFromWstETH(uint256 requestId) external virtual;

    function requestWithdrawFromWstETH(uint256 amountToRedeem)
        external
        virtual
        returns (uint256[] memory requestIds);

    /**********************************************************************************************/
    /*** WEETHFacet actions                                                                     ***/
    /**********************************************************************************************/

    function LIMIT_WEETH_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_WEETH_REQUEST_WITHDRAW() external pure virtual returns (bytes32);

    function depositToWeETH(uint256 amount, uint256 minSharesOut)
        external
        virtual
        returns (uint256 shares);

    function claimWithdrawalFromWeETH(address weethModule, uint256 requestId)
        external
        virtual
        returns (uint256 ethReceived);

    function requestWithdrawFromWeETH(
        address weethModule,
        uint256 weethShares,
        uint256 minEETHShares
    )
        external
        virtual
        returns (uint256 requestId);

    /**********************************************************************************************/
    /*** FarmFacet actions                                                                      ***/
    /**********************************************************************************************/

    function LIMIT_FARM_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_FARM_WITHDRAW() external pure virtual returns (bytes32);

    function depositToFarm(address farm, uint256 amount) external virtual;

    function withdrawFromFarm(address farm, uint256 amount) external virtual;

    /**********************************************************************************************/
    /*** SuperstateFacet actions                                                                ***/
    /**********************************************************************************************/

    function LIMIT_SUPERSTATE_SUBSCRIBE() external pure virtual returns (bytes32);

    function subscribeSuperstate(uint256 usdcAmount) external virtual;

    /**********************************************************************************************/
    /*** PSMFacet actions                                                                       ***/
    /**********************************************************************************************/

    function LIMIT_USDS_TO_USDC() external pure virtual returns (bytes32);

    function swapUSDSToUSDC(uint256 usdcAmount) external virtual;

    function swapUSDCToUSDS(uint256 usdcAmount) external virtual;

    function psmTo18ConversionFactor() external view virtual returns (uint256);

}
