// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController }     from "../../src/interfaces/IController.sol";
import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

interface IForeignControllerFull is IController {

    /**********************************************************************************************/
    /*** AaveFacet actions                                                                      ***/
    /**********************************************************************************************/

    function setAaveMaxSlippage(address aToken, uint256 maxSlippage) external;

    function depositAave(address aToken, uint256 amount) external;

    function withdrawAave(address aToken, uint256 amount)
        external
        returns (uint256 amountWithdrawn);

    function getAaveMaxSlippage(address aToken) external view returns (uint256);

    function getAaveDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32 key);

    function getAaveWithdrawRateLimitKey(address aToken, address pool)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CCTPFacet actions                                                                      ***/
    /**********************************************************************************************/

    function setCCTPDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate)
        external;

    function toCCTPRateLimitKey() external pure returns (bytes32 key);

    function getCCTPDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function getCCTPToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CentrifugeFacet actions                                                                ***/
    /**********************************************************************************************/

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function cancelCentrifugeDepositRequest(address token) external;

    function claimCentrifugeCancelDepositRequest(address token) external;

    function cancelCentrifugeRedeemRequest(address token) external;

    function claimCentrifugeCancelRedeemRequest(address token) external;

    function transferSharesCentrifuge(address token, uint128 amount, uint16 centrifugeId)
        external
        payable;

    function getCentrifugeRecipient(uint16 centrifugeId) external view returns (bytes32);

    function getCentrifugeCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getCentrifugeClaimCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getCentrifugeCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function getCentrifugeClaimCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function getCentrifugeTransferRateLimitKey(address token, uint16 centrifugeId, address spoke)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CurveFacet actions                                                                     ***/
    /**********************************************************************************************/

    function setCurveMaxSlippage(address pool, uint256 maxSlippage) external;

    function swapCurve(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut);

    function addLiquidityCurve(address pool, uint256[] calldata depositAmounts, uint256 minLpAmount)
        external
        returns (uint256 shares);

    function removeLiquidityCurve(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        returns (uint256[] memory withdrawnTokens);

    function getCurveMaxSlippage(address pool) external view returns (uint256);

    function getCurveAggregateDepositRateLimitKey(address pool) external pure returns (bytes32 key);

    function getCurveAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getCurveSwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getCurveWithdrawRateLimitKey(address pool) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** ERC4626Facet actions                                                                   ***/
    /**********************************************************************************************/

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 shares);

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external
        returns (uint256 shares);

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assets);

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256);

    function maxExchangeRates(address token) external view returns (uint256);

    function getERC4626DepositRateLimitKey(address token, address asset)
        external
        pure
        returns (bytes32 key);

    function getERC4626WithdrawRateLimitKey(address token) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** ERC7540Facet actions                                                                   ***/
    /**********************************************************************************************/

    function requestDepositERC7540(address token, uint256 amount) external;

    function claimDepositERC7540(address token) external;

    function requestRedeemERC7540(address token, uint256 shares) external;

    function claimRedeemERC7540(address token) external;

    function getERC7540RequestDepositRateLimitKey(address token, address asset)
        external
        pure
        returns (bytes32 key);

    function getERC7540ClaimDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function getERC7540RequestRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function getERC7540ClaimRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** LayerZeroFacet actions                                                                 ***/
    /**********************************************************************************************/

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function transferTokenLayerZero(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        payable;

    function layerZeroRecipients(uint32 destinationEndpointId) external view returns (bytes32);

    function getLayerZeroTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    )
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** MerklFacet actions                                                                     ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address distributor, address operator) external;

    function getMerklToggleOperatorRateLimitKey(address distributor, address operator)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** PendleFacet actions                                                                    ***/
    /**********************************************************************************************/

    function redeemPendlePT(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut)
        external;

    function getPendleRedeemRateLimitKey(address pendleMarket, address pt)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** PSM3Facet actions                                                                      ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount) external returns (uint256 shares);

    function withdrawPSM(address asset, uint256 maxAmount)
        external
        returns (uint256 assetsWithdrawn);

    function getPSMDepositRateLimitKey(address asset) external pure returns (bytes32 key);

    function getPSMWithdrawRateLimitKey(address asset) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SparkVaultFacet actions                                                                ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount) external;

    function getSparkVaultTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** TransferAssetFacet actions                                                             ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount) external;

    function getTransferAssetTransferRateLimitKey(address asset, address destination)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** UniswapV3Facet actions                                                                 ***/
    /**********************************************************************************************/

    function setUniswapV3MaxSlippage(address pool, uint256 maxSlippage) external;

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta) external;

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    function setUniswapV3TWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        external
        returns (uint256 amountOut);

    function addLiquidityUniswapV3(
        address                               pool,
        uint256                               tokenId,
        IUniswapV3Facet.Ticks        calldata ticks,
        IUniswapV3Facet.TokenAmounts calldata target,
        IUniswapV3Facet.TokenAmounts calldata min,
        uint256                               deadline
    )
        external
        returns (uint256, uint128, IUniswapV3Facet.TokenAmounts memory);

    function removeLiquidityUniswapV3(
        address                               pool,
        uint256                               tokenId,
        uint128                               liquidity,
        IUniswapV3Facet.TokenAmounts calldata min,
        uint256                               deadline
    )
        external
        returns (IUniswapV3Facet.TokenAmounts memory);

    function getUniswapV3MaxSlippage(address pool) external view returns (uint256);

    function getUniswapV3PoolMaxTickDelta(address pool) external view returns (uint24);

    function getUniswapV3AddLiquidityTickBounds(address pool)
        external
        view
        returns (int24 lower, int24 upper);

    function getUniswapV3TWAPSecondsAgo(address pool) external view returns (uint32);

    function getUniswapV3AggregateDepositRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3AssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3SwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3WithdrawRateLimitKey(address pool) external pure returns (bytes32 key);

}
