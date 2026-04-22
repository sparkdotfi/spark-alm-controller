// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController }     from "../../src/interfaces/IController.sol";
import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

import { Controller } from "../../src/Controller.sol";

abstract contract IForeignControllerFull is IController, Controller {

    /**********************************************************************************************/
    /*** AaveFacet actions                                                                      ***/
    /**********************************************************************************************/

    function getAaveMaxSlippage(address aToken) external view virtual returns (uint256);

    function depositAave(address aToken, uint256 amount) external virtual;

    function LIMIT_AAVE_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_AAVE_WITHDRAW() external pure virtual returns (bytes32);

    function setAaveMaxSlippage(address aToken, uint256 maxSlippage) external virtual;

    function withdrawAave(address aToken, uint256 amount)
        external virtual returns (uint256 amountWithdrawn);

    /**********************************************************************************************/
    /*** CCTPFacet actions                                                                      ***/
    /**********************************************************************************************/

    function getCCTPMaxFeeCap() external view virtual returns (uint256);

    function LIMIT_USDC_TO_CCTP() external pure virtual returns (bytes32);

    function LIMIT_USDC_TO_DOMAIN() external pure virtual returns (bytes32);

    function getCCTPMintRecipient(uint32 destinationDomain) external view virtual returns (bytes32);

    function setCCTPMaxFeeCap(uint256 maxFeeCap) external virtual;

    function setCCTPMintRecipient(uint32 destinationDomain, bytes32 recipient) external virtual;

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain) external virtual;

    function transferUSDCToCCTPWithFee(uint256 usdcAmount, uint256 maxFee, uint32 destinationDomain)
        external virtual;

    /**********************************************************************************************/
    /*** CentrifugeFacet actions                                                                ***/
    /**********************************************************************************************/

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient) external virtual;

    function cancelCentrifugeDepositRequest(address token) external virtual;

    function claimCentrifugeCancelDepositRequest(address token) external virtual;

    function cancelCentrifugeRedeemRequest(address token) external virtual;

    function claimCentrifugeCancelRedeemRequest(address token) external virtual;

    function transferSharesCentrifuge(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        virtual;

    function LIMIT_CENTRIFUGE_TRANSFER() external pure virtual returns (bytes32); // NOTE: DEPOSIT, REDEEM keys will be reused from ERC7450Facet wiring

    function getCentrifugeRecipient(uint16 centrifugeId) external view virtual returns (bytes32);

    /**********************************************************************************************/
    /*** CurveFacet actions                                                                     ***/
    /**********************************************************************************************/

    function addLiquidityCurve(address pool, uint256[] calldata depositAmounts, uint256 minLpAmount)
        external virtual returns (uint256 shares);

    function getCurveMaxSlippage(address pool) external view virtual returns (uint256);

    function LIMIT_CURVE_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_CURVE_SWAP() external pure virtual returns (bytes32);

    function LIMIT_CURVE_WITHDRAW() external pure virtual returns (bytes32);

    function removeLiquidityCurve(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    ) external virtual returns (uint256[] memory withdrawnTokens);

    function setCurveMaxSlippage(address pool, uint256 maxSlippage) external virtual;

    function swapCurve(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    ) external virtual returns (uint256 amountOut);

    /**********************************************************************************************/
    /*** ERC4626Facet actions                                                                   ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external
        virtual
        returns (uint256 shares);

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        virtual
        returns (uint256 assets);

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
    /*** LayerZeroFacet actions                                                                 ***/
    /**********************************************************************************************/

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external virtual;

    function transferTokenLayerZero(
        address oftAddress,
        uint256 amount,
        uint32 destinationEndpointId
    ) external payable virtual;

    function LIMIT_LAYERZERO_TRANSFER() external pure virtual returns (bytes32);

    function layerZeroRecipients(
        uint32 destinationEndpointId
    ) external view virtual returns (bytes32);

    /**********************************************************************************************/
    /*** MerklFacet actions                                                                     ***/
    /**********************************************************************************************/

    function setMerklDistributor(address distributor) external virtual;

    function toggleOperatorMerkl(address operator) external virtual;

    function merklDistributor() external view virtual returns (address);

    /**********************************************************************************************/
    /*** PendleFacet actions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_PENDLE_PT_REDEEM() external pure virtual returns (bytes32);

    function redeemPendlePT(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut) external virtual;

    /**********************************************************************************************/
    /*** PSM3Facet actions                                                                      ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount) external virtual returns (uint256 shares);

    function withdrawPSM(
        address asset,
        uint256 maxAmount
    ) external virtual returns (uint256 assetsWithdrawn);

    function LIMIT_PSM_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_PSM_WITHDRAW() external pure virtual returns (bytes32);

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
    /*** UniswapV3Facet actions                                                                 ***/
    /**********************************************************************************************/

    function addLiquidityUniswapV3(
        address                      pool,
        uint256                      tokenId,
        IUniswapV3Facet.Ticks        memory ticks,
        IUniswapV3Facet.TokenAmounts memory target,
        IUniswapV3Facet.TokenAmounts memory min,
        uint256                      deadline
    )
        external
        virtual
        returns (uint256 tokenId_, uint128 liquidity_, IUniswapV3Facet.TokenAmounts memory amounts_);

    function removeLiquidityUniswapV3(
        address                      pool,
        uint256                      tokenId,
        uint128                      liquidity,
        IUniswapV3Facet.TokenAmounts memory min,
        uint256                      deadline
    )
        external
        virtual
        returns (IUniswapV3Facet.TokenAmounts memory amounts);

    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        external
        virtual
        returns (uint256 amountOut);

    function setUniswapV3MaxSlippage(address pool, uint256 maxSlippage) external virtual;

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta) external virtual;

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound) external virtual;

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound) external virtual;

    function setUniswapV3TWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external virtual;

    function LIMIT_UNISWAP_V3_DEPOSIT() external pure virtual returns (bytes32);

    function LIMIT_UNISWAP_V3_SWAP() external pure virtual returns (bytes32);

    function LIMIT_UNISWAP_V3_WITHDRAW() external pure virtual returns (bytes32);

    function getUniswapV3MaxSlippage(address pool) external view virtual returns (uint256);

    function getUniswapV3PoolMaxTickDelta(address pool) external view virtual returns (uint24);

    function getUniswapV3AddLiquidityTickBounds(address pool) external view virtual returns (int24 lower, int24 upper);

    function getUniswapV3TWAPSecondsAgo(address pool) external view virtual returns (uint32);

}
