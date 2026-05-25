// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController }     from "../../src/interfaces/IController.sol";
import { ILayerZeroFacet } from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

interface IMainnetControllerFull is IController {

    /**********************************************************************************************/
    /*** AaveFacet actions                                                                      ***/
    /**********************************************************************************************/

    function aave_VERSION() external pure returns (string memory);

    function aave_setMaxSlippage(address aToken, uint256 maxSlippage) external;

    function aave_deposit(address aToken, uint256 amount) external;

    function aave_withdraw(address aToken, uint256 amount)
        external
        returns (uint256 amountWithdrawn);

    function aave_getMaxSlippage(address aToken) external view returns (uint256);

    function aave_getDepositRateLimitKey(address aToken, address pool, address underlyingAsset)
        external
        pure
        returns (bytes32 key);

    function aave_getWithdrawRateLimitKey(address aToken, address pool)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** BasinFacet actions                                                                     ***/
    /**********************************************************************************************/

    function basin_VERSION() external pure returns (string memory);

    function basin_deposit(address basin, address asset, uint256 amount, uint256 minSharesOut)
        external returns (uint256 shares);

    function basin_withdraw(
        address basin,
        address asset,
        uint256 maxAmount,
        uint256 minConversionRate
    ) external returns (uint256 assetsWithdrawn);

    function basin_getDepositRateLimitKey(address basin, address asset)
        external
        pure
        returns (bytes32 key);

    function basin_getWithdrawRateLimitKey(address basin, address asset)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CCTPFacet actions                                                                      ***/
    /**********************************************************************************************/

    function cctp_VERSION() external pure returns (string memory);

    function cctp_DESTINATION_CALLER() external pure returns (bytes32);

    function cctp_MIN_FINALITY_THRESHOLD() external pure returns (uint32);

    function cctp_cctp() external view returns (address);

    function cctp_usdc() external view returns (address);

    function cctp_setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate)
        external;

    function cctp_toCCTPRateLimitKey() external pure returns (bytes32 key);

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CentrifugeFacet actions                                                                ***/
    /**********************************************************************************************/

    function centrifuge_VERSION() external pure returns (string memory);

    function centrifuge_REQUEST_ID() external pure returns (uint256);

    function centrifuge_setRecipient(uint16 centrifugeId, bytes32 recipient) external;

    function centrifuge_cancelDepositRequest(address token) external;

    function centrifuge_claimCancelDepositRequest(address token) external;

    function centrifuge_cancelRedeemRequest(address token) external;

    function centrifuge_claimCancelRedeemRequest(address token) external;

    function centrifuge_transferShares(address token, uint128 amount, uint16 centrifugeId)
        external
        payable;

    function centrifuge_getRecipient(uint16 centrifugeId) external view returns (bytes32);

    function centrifuge_getCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function centrifuge_getClaimCancelDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function centrifuge_getCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function centrifuge_getClaimCancelRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function centrifuge_getTransferRateLimitKey(address token, uint16 centrifugeId, address spoke)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** CurveFacet actions                                                                     ***/
    /**********************************************************************************************/

    function curve_VERSION() external pure returns (string memory);

    function curve_setMaxSlippage(address pool, uint256 maxSlippage) external;

    function curve_swap(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut);

    function curve_addLiquidity(address pool, uint256[] calldata inputAmounts, uint256 minShares)
        external
        returns (uint256 shares);

    function curve_removeLiquidity(
        address            pool,
        uint256            shares,
        uint256[] calldata minWithdrawAmounts
    )
        external
        returns (uint256[] memory withdrawnAmounts);

    function curve_getMaxSlippage(address pool) external view returns (uint256);

    function curve_getAggregateDepositRateLimitKey(address pool) external pure returns (bytes32 key);

    function curve_getAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function curve_getSwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function curve_getAggregateWithdrawRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function curve_getAssetWithdrawRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** DaiUsdsFacet actions                                                                   ***/
    /**********************************************************************************************/

    function daiUSDS_VERSION() external pure returns (string memory);

    function daiUSDS_dai() external view returns (address);

    function daiUSDS_daiUSDS() external view returns (address);

    function daiUSDS_usds() external view returns (address);

    function daiUSDS_swapUSDSToDAI(uint256 usdsAmount) external;

    function daiUSDS_swapDAIToUSDS(uint256 daiAmount) external;

    function daiUSDS_daiToUSDSSwapRateLimitKey() external pure returns (bytes32 key);

    function daiUSDS_usdsToDAISwapRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** ERC4626Facet actions                                                                   ***/
    /**********************************************************************************************/

    function erc4626_VERSION() external pure returns (string memory);

    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function erc4626_deposit(address token, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 shares);

    function erc4626_withdraw(address token, uint256 amount, uint256 maxSharesIn)
        external
        returns (uint256 shares);

    function erc4626_redeem(address token, uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assets);

    function erc4626_EXCHANGE_RATE_PRECISION() external pure returns (uint256);

    function erc4626_getMaxExchangeRate(address token) external view returns (uint256);

    function erc4626_getDepositRateLimitKey(address token, address asset)
        external
        pure
        returns (bytes32 key);

    function erc4626_getWithdrawRateLimitKey(address token) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** ERC7540Facet actions                                                                   ***/
    /**********************************************************************************************/

    function erc7540_VERSION() external pure returns (string memory);

    function erc7540_requestDeposit(address token, uint256 amount) external;

    function erc7540_claimDeposit(address token) external;

    function erc7540_requestRedeem(address token, uint256 shares) external;

    function erc7540_claimRedeem(address token) external;

    function erc7540_getRequestDepositRateLimitKey(address token, address asset)
        external
        pure
        returns (bytes32 key);

    function erc7540_getClaimDepositRateLimitKey(address token) external pure returns (bytes32 key);

    function erc7540_getRequestRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    function erc7540_getClaimRedeemRateLimitKey(address token) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** EthenaFacet actions                                                                    ***/
    /**********************************************************************************************/

    function ethena_VERSION() external pure returns (string memory);

    function ethena_minter() external view returns (address);

    function ethena_susde() external view returns (address);

    function ethena_usdc() external view returns (address);

    function ethena_usde() external view returns (address);

    function ethena_setDelegatedSigner(address delegatedSigner) external;

    function ethena_removeDelegatedSigner(address delegatedSigner) external;

    function ethena_prepareMint(uint256 usdcAmount) external;

    function ethena_prepareBurn(uint256 usdeAmount) external;

    function ethena_cooldownAssets(uint256 usdeAmount) external returns (uint256 cooldownShares);

    function ethena_cooldownShares(uint256 susdeAmount) external returns (uint256 cooldownAssets);

    function ethena_unstake() external;

    function ethena_setDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    function ethena_removeDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    function ethena_mintRateLimitKey() external pure returns (bytes32 key);

    function ethena_burnRateLimitKey() external pure returns (bytes32 key);

    function ethena_cooldownRateLimitKey() external pure returns (bytes32 key);

    function ethena_unstakeRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** FarmFacet actions                                                                      ***/
    /**********************************************************************************************/

    function farm_VERSION() external pure returns (string memory);

    function farm_deposit(address farm, uint256 amount) external;

    function farm_claimReward(address farm) external returns (uint256 reward);

    function farm_withdraw(address farm, uint256 amount) external;

    function farm_getClaimRewardRateLimitKey(address farm) external pure returns (bytes32 key);

    function farm_getDepositRateLimitKey(address farm, address stakingToken)
        external
        pure
        returns (bytes32 key);

    function farm_getWithdrawRateLimitKey(address farm) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** LayerZeroFacet actions                                                                 ***/
    /**********************************************************************************************/

    function layerZero_VERSION() external pure returns (string memory);

    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function layerZero_transfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        payable;

    function layerZero_getRecipient(uint32 destinationEndpointId) external view returns (bytes32);

    function layerZero_getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    )
        external
        pure
        returns (bytes32 key);

    function layerZero_quoteTransfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        returns (
            ILayerZeroFacet.SendParam    memory sendParams,
            ILayerZeroFacet.MessagingFee memory fee
        );

    /**********************************************************************************************/
    /*** MapleFacet actions                                                                     ***/
    /**********************************************************************************************/

    function maple_VERSION() external pure returns (string memory);

    function maple_requestRedemption(address mapleToken, uint256 shares) external;

    function maple_cancelRedemption(address mapleToken, uint256 shares) external;

    function maple_getCancelRedeemRateLimitKey(address mapleToken) external pure returns (bytes32 key);

    function maple_getRequestRedeemRateLimitKey(address mapleToken)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** MerklFacet actions                                                                     ***/
    /**********************************************************************************************/

    function merkl_VERSION() external pure returns (string memory);

    function merkl_toggleOperator(address distributor, address operator) external;

    function merkl_getToggleOperatorRateLimitKey(address distributor, address operator)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** OTCFacet actions                                                                       ***/
    /**********************************************************************************************/

    function otc_VERSION() external pure returns (string memory);

    function otc_setMaxSlippage(address exchange, uint256 maxSlippage) external;

    function otc_setBuffer(address exchange, address otcBuffer) external;

    function otc_setRechargeRate(address exchange, uint256 normalizedRate) external;

    function otc_send(address exchange, address asset, uint256 amount) external;

    function otc_claim(address exchange, address asset) external;

    function otc_getBuffer(address exchange) external view returns (address);

    function otc_getMaxSlippage(address exchange) external view returns (uint256);

    function otc_getRechargeRate(address exchange) external view returns (uint256);

    function otc_getState(address exchange)
        external
        view
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed);

    function otc_getClaimWithRecharge(address exchange) external view returns (uint256);

    function otc_getIsSwapReady(address exchange) external view returns (bool);

    function otc_getSendRateLimitKey(address exchange, address asset)
        external
        pure
        returns (bytes32 key);

    function otc_getClaimRateLimitKey(address exchange, address asset)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** PendleFacet actions                                                                    ***/
    /**********************************************************************************************/

    function pendle_VERSION() external pure returns (string memory);

    function pendle_router() external view returns (address);

    function pendle_redeem(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut)
        external;

    function pendle_getRedeemRateLimitKey(address pendleMarket, address pt)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** PSMFacet actions                                                                       ***/
    /**********************************************************************************************/

    function psm_VERSION() external pure returns (string memory);

    function psm_dai() external view returns (address);

    function psm_daiUSDS() external view returns (address);

    function psm_psm() external view returns (address);

    function psm_usdc() external view returns (address);

    function psm_usds() external view returns (address);

    function psm_swapUSDSToUSDC(uint256 usdcAmount) external;

    function psm_swapUSDCToUSDS(uint256 usdcAmount) external;

    function psm_to18ConversionFactor() external view returns (uint256);

    function psm_usdcToUSDSSwapRateLimitKey() external pure returns (bytes32 key);

    function psm_usdsToUSDCSwapRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SparkVaultFacet actions                                                                ***/
    /**********************************************************************************************/

    function sparkVault_VERSION() external pure returns (string memory);

    function sparkVault_take(address sparkVault, uint256 assetAmount) external;

    function sparkVault_getTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SuperstateFacet actions                                                                ***/
    /**********************************************************************************************/

    function superstate_VERSION() external pure returns (string memory);

    function superstate_usdc() external view returns (address);

    function superstate_ustb() external view returns (address);

    function superstate_subscribe(uint256 usdcAmount) external;

    function superstate_subscribeRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** TransferAssetFacet actions                                                             ***/
    /**********************************************************************************************/

    function transferAsset_VERSION() external pure returns (string memory);

    function transferAsset_transfer(address asset, address destination, uint256 amount) external;

    function transferAsset_getTransferRateLimitKey(address asset, address destination)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** UniswapV3Facet actions                                                                 ***/
    /**********************************************************************************************/

    function uniswapV3_VERSION() external pure returns (string memory);

    function uniswapV3_MAX_TICK_DELTA() external pure returns (uint24);

    function uniswapV3_MIN_TICK() external pure returns (int24);

    function uniswapV3_MAX_TICK() external pure returns (int24);

    function uniswapV3_positionManager() external view returns (address);

    function uniswapV3_router() external view returns (address);

    function uniswapV3_setMaxSlippage(address pool, uint256 maxSlippage) external;

    function uniswapV3_setMaxTickDelta(address pool, uint24 maxTickDelta) external;

    function uniswapV3_setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;

    function uniswapV3_setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;

    function uniswapV3_setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;

    function uniswapV3_swap(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  tickDelta
    )
        external
        returns (uint256 amountOut);

    function uniswapV3_addLiquidity(
        address                               pool,
        uint256                               tokenId,
        IUniswapV3Facet.Ticks        calldata ticks,
        IUniswapV3Facet.TokenAmounts calldata target,
        IUniswapV3Facet.TokenAmounts calldata min,
        uint256                               deadline
    )
        external
        returns (uint256, uint128, IUniswapV3Facet.TokenAmounts memory);

    function uniswapV3_removeLiquidity(
        address                               pool,
        uint256                               tokenId,
        uint128                               liquidity,
        IUniswapV3Facet.TokenAmounts calldata min,
        uint256                               deadline
    )
        external
        returns (IUniswapV3Facet.TokenAmounts memory);

    function uniswapV3_getAggregateDepositRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getLiquidityTickBounds(address pool)
        external
        view
        returns (int24 lower, int24 upper);

    function uniswapV3_getMaxSlippage(address pool) external view returns (uint256);

    function uniswapV3_getMaxTickDelta(address pool) external view returns (uint24);

    function uniswapV3_getSwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getTWAPSecondsAgo(address pool) external view returns (uint32);

    function uniswapV3_getAggregateWithdrawRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getAssetWithdrawRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** UniswapV4Facet actions                                                                 ***/
    /**********************************************************************************************/

    function uniswapV4_VERSION() external pure returns (string memory);

    function uniswapV4_permit2() external view returns (address);

    function uniswapV4_positionManager() external view returns (address);

    function uniswapV4_router() external view returns (address);

    function uniswapV4_setMaxSlippage(bytes32 poolId, uint256 maxSlippage) external;

    function uniswapV4_setTickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external;

    function uniswapV4_mintPosition(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external;

    function uniswapV4_increasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external;

    function uniswapV4_decreasePosition(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external;

    function uniswapV4_swap(bytes32 poolId, address tokenIn, uint128 amountIn, uint128 amountOutMin)
        external;

    function uniswapV4_getAggregateDepositRateLimitKey(bytes32 poolId)
        external
        pure
        returns (bytes32 key);

    function uniswapV4_getAssetDepositRateLimitKey(bytes32 poolId, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV4_getMaxSlippage(bytes32 poolId) external view returns (uint256);

    function uniswapV4_getSwapRateLimitKey(bytes32 poolId, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV4_getTickLimits(bytes32 poolId)
        external
        view
        returns (int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing);

    function uniswapV4_getAggregateWithdrawRateLimitKey(bytes32 poolId)
        external
        pure
        returns (bytes32 key);

    function uniswapV4_getAssetWithdrawRateLimitKey(bytes32 poolId, address token)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** USDSFacet actions                                                                      ***/
    /**********************************************************************************************/

    function usds_VERSION() external pure returns (string memory);

    function usds_usds() external view returns (address);

    function usds_setVault(address vault) external;

    function usds_mint(uint256 usdsAmount) external;

    function usds_burn(uint256 usdsAmount) external;

    function usds_vault() external view returns (address);

    function usds_mintRateLimitKey() external pure returns (bytes32 key);

    function usds_burnRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** WEETHFacet actions                                                                     ***/
    /**********************************************************************************************/

    function weeth_VERSION() external pure returns (string memory);

    function weeth_weeth() external view returns (address);

    function weeth_weth() external view returns (address);

    function weeth_deposit(uint256 amount, uint256 minSharesOut) external returns (uint256 shares);

    function weeth_requestWithdraw(
        address weethModule,
        uint256 weethShares,
        uint256 minEETHShares
    )
        external
        returns (uint256 requestId);

    function weeth_claimWithdrawal(address weethModule, uint256 requestId)
        external
        returns (uint256 ethReceived);

    function weeth_getDepositRateLimitKey(address eeth, address liquidityPool)
        external
        pure
        returns (bytes32 key);

    function weeth_getRequestWithdrawRateLimitKey(
        address weethModule,
        address eeth,
        address liquidityPool
    )
        external
        pure
        returns (bytes32 key);

    function weeth_getClaimWithdrawRateLimitKey(address weethModule)
        external
        pure
        returns (bytes32 key);

    /**********************************************************************************************/
    /*** WrapProxyETHFacet actions                                                              ***/
    /**********************************************************************************************/

    function wrapProxyETH_VERSION() external pure returns (string memory);

    function wrapProxyETH_weth() external view returns (address);

    function wrapProxyETH_wrapAll() external;

    function wrapProxyETH_wrapRateLimitKey() external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** WSTETHFacet actions                                                                    ***/
    /**********************************************************************************************/

    function wsteth_VERSION() external pure returns (string memory);

    function wsteth_weth() external view returns (address);

    function wsteth_withdrawQueue() external view returns (address);

    function wsteth_wsteth() external view returns (address);

    function wsteth_deposit(uint256 amount) external;

    function wsteth_requestWithdraw(uint256 amountToRedeem)
        external
        returns (uint256[] memory requestIds);

    function wsteth_claimWithdrawal(uint256 requestId) external;

    function wsteth_depositRateLimitKey() external pure returns (bytes32 key);

    function wsteth_requestWithdrawRateLimitKey() external pure returns (bytes32 key);

    function wsteth_claimWithdrawRateLimitKey() external pure returns (bytes32 key);

}
