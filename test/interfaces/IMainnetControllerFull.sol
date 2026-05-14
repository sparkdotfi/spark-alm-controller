// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController }     from "../../src/interfaces/IController.sol";
import { ILayerZeroFacet } from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

interface IMainnetControllerFull is IController {

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
    /*** BasinFacet actions                                                                     ***/
    /**********************************************************************************************/

    function depositBasin(address basin, address asset, uint256 amount, uint256 minSharesOut)
        external returns (uint256 shares);

    function withdrawBasin(
        address basin,
        address asset,
        uint256 maxAmount,
        uint256 minConversionRate
    ) external returns (uint256 assetsWithdrawn);

    function getBasinDepositRateLimitKey(address basin, address asset)
        external
        pure
        returns (bytes32 key);

    function getBasinWithdrawRateLimitKey(address basin, address asset)
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
    /*** DaiUsdsFacet actions                                                                   ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external;

    function swapDAIToUSDS(uint256 daiAmount) external;

    function daiToUSDSSwapRateLimitKey() external pure returns (bytes32 key);

    function usdsToDAISwapRateLimitKey() external pure returns (bytes32 key);

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
    /*** EthenaFacet actions                                                                    ***/
    /**********************************************************************************************/

    function setEthenaDelegatedSigner(address delegatedSigner) external;

    function removeEthenaDelegatedSigner(address delegatedSigner) external;

    function prepareUSDeMint(uint256 usdcAmount) external;

    function prepareUSDeBurn(uint256 usdeAmount) external;

    function cooldownAssetsSUSDe(uint256 usdeAmount) external returns (uint256 cooldownShares);

    function cooldownSharesSUSDe(uint256 susdeAmount) external returns (uint256 cooldownAssets);

    function unstakeSUSDe() external;

    function setEthenaDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    function removeEthenaDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    function usdeMintRateLimitKey() external pure returns (bytes32 key);

    function usdeBurnRateLimitKey() external pure returns (bytes32 key);

    function usdeCooldownRateLimitKey() external pure returns (bytes32 key);

    function usdeUnstakeRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** FarmFacet actions                                                                      ***/
    /**********************************************************************************************/

    function depositToFarm(address farm, uint256 amount) external;

    function claimRewardFromFarm(address farm) external returns (uint256 reward);

    function withdrawFromFarm(address farm, uint256 amount) external;

    function getFarmClaimRewardRateLimitKey(address farm) external pure returns (bytes32 key);

    function getFarmDepositRateLimitKey(address farm, address stakingToken)
        external
        pure
        returns (bytes32 key);

    function getFarmWithdrawRateLimitKey(address farm) external pure returns (bytes32 key);

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

    function quoteTransferLayerZero(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        returns (
            ILayerZeroFacet.SendParam    memory sendParams,
            ILayerZeroFacet.MessagingFee memory fee
        );

    /**********************************************************************************************/
    /*** MapleFacet actions                                                                     ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares) external;

    function cancelMapleRedemption(address mapleToken, uint256 shares) external;

    function getMapleCancelRedeemRateLimitKey(address mapleToken) external pure returns (bytes32 key);

    function getMapleRequestRedeemRateLimitKey(address mapleToken)
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
    /*** OTCFacet actions                                                                       ***/
    /**********************************************************************************************/

    function setOTCMaxSlippage(address exchange, uint256 maxSlippage) external;

    function setOTCBuffer(address exchange, address otcBuffer) external;

    function setOTCRechargeRate(address exchange, uint256 normalizedRate) external;

    function otcSend(address exchange, address asset, uint256 amount) external;

    function otcClaim(address exchange, address asset) external;

    function getOTCBuffer(address exchange) external view returns (address);

    function getOTCMaxSlippage(address exchange) external view returns (uint256);

    function getOTCRechargeRate(address exchange) external view returns (uint256);

    function otcs(address exchange)
        external
        view
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed);

    function getOtcClaimWithRecharge(address exchange) external view returns (uint256);

    function isOtcSwapReady(address exchange) external view returns (bool);

    function getOTCSendRateLimitKey(address exchange, address asset)
        external
        pure
        returns (bytes32 key);

    function getOTCClaimRateLimitKey(address exchange, address asset)
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
    /*** PSMFacet actions                                                                       ***/
    /**********************************************************************************************/

    function swapUSDSToUSDC(uint256 usdcAmount) external;

    function swapUSDCToUSDS(uint256 usdcAmount) external;

    function psmTo18ConversionFactor() external view returns (uint256);

    function psmUSDCToUSDSSwapRateLimitKey() external pure returns (bytes32 key);

    function psmUSDSToUSDCSwapRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SparkVaultFacet actions                                                                ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount) external;

    function getSparkVaultTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SuperstateFacet actions                                                                ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external;

    function superstateSubscribeRateLimitKey() external pure returns (bytes32 key);

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

    function getUniswapV3AggregateDepositRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3AssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3AddLiquidityTickBounds(address pool)
        external
        view
        returns (int24 lower, int24 upper);

    function getUniswapV3MaxSlippage(address pool) external view returns (uint256);

    function getUniswapV3PoolMaxTickDelta(address pool) external view returns (uint24);

    function getUniswapV3SwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function getUniswapV3TWAPSecondsAgo(address pool) external view returns (uint32);

    function getUniswapV3WithdrawRateLimitKey(address pool) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** UniswapV4Facet actions                                                                 ***/
    /**********************************************************************************************/

    function setUniswapV4MaxSlippage(bytes32 poolId, uint256 maxSlippage) external;

    function setUniswapV4TickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external;

    function mintPositionUniswapV4(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external;

    function increaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external;

    function decreaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external;

    function swapUniswapV4(bytes32 poolId, address tokenIn, uint128 amountIn, uint128 amountOutMin)
        external;

    function getUniswapV4AggregateDepositRateLimitKey(bytes32 poolId)
        external
        pure
        returns (bytes32 key);

    function getUniswapV4AssetDepositRateLimitKey(bytes32 poolId, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV4MaxSlippages(bytes32 poolId) external view returns (uint256);

    function getUniswapV4SwapRateLimitKey(bytes32 poolId, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV4TickLimits(bytes32 poolId)
        external
        view
        returns (int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing);

    function getUniswapV4WithdrawRateLimitKey(bytes32 poolId) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** USDSFacet actions                                                                      ***/
    /**********************************************************************************************/

    function setUSDSVault(address vault) external;

    function mintUSDS(uint256 usdsAmount) external;

    function burnUSDS(uint256 usdsAmount) external;

    function usdsVault() external view returns (address);

    function usdsMintRateLimitKey() external pure returns (bytes32 key);

    function usdsBurnRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** WEETHFacet actions                                                                     ***/
    /**********************************************************************************************/

    function depositToWeETH(uint256 amount, uint256 minSharesOut) external returns (uint256 shares);

    function requestWithdrawFromWeETH(
        address weethModule,
        uint256 weethShares,
        uint256 minEETHShares
    )
        external
        returns (uint256 requestId);

    function claimWithdrawalFromWeETH(address weethModule, uint256 requestId)
        external
        returns (uint256 ethReceived);

    function getWEETHDepositRateLimitKey(address eeth, address liquidityPool)
        external
        pure
        returns (bytes32 key);

    function getWEETHRequestWithdrawRateLimitKey(
        address weethModule,
        address eeth,
        address liquidityPool
    )
        external
        pure
        returns (bytes32 key);

    function getWEETHClaimWithdrawRateLimitKey(address weethModule)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** WrapProxyETHFacet actions                                                              ***/
    /**********************************************************************************************/

    function wrapAllProxyETH() external;

    function wrapAllProxyETHRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** WSTETHFacet actions                                                                    ***/
    /**********************************************************************************************/

    function depositToWstETH(uint256 amount) external;

    function requestWithdrawFromWstETH(uint256 amountToRedeem)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawalFromWstETH(uint256 requestId) external;

    function wstethDepositRateLimitKey() external pure returns (bytes32 key);

    function wstethRequestWithdrawRateLimitKey() external pure returns (bytes32 key);

    function wstethClaimWithdrawRateLimitKey() external pure returns (bytes32 key);

}
