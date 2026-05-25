// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IController }     from "../../src/interfaces/IController.sol";
import { ILayerZeroFacet } from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { IUniswapV3Facet } from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

interface IForeignControllerFull is IController {

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
    /*** MerklFacet actions                                                                     ***/
    /**********************************************************************************************/

    function merkl_VERSION() external pure returns (string memory);

    function merkl_toggleOperator(address distributor, address operator) external;

    function merkl_getToggleOperatorRateLimitKey(address distributor, address operator)
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
    /*** PSM3Facet actions                                                                      ***/
    /**********************************************************************************************/

    function psm3_VERSION() external pure returns (string memory);

    function psm3_psm() external view returns (address);

    function psm3_deposit(address asset, uint256 amount) external returns (uint256 shares);

    function psm3_withdraw(address asset, uint256 maxAmount)
        external
        returns (uint256 assetsWithdrawn);

    function psm3_getDepositRateLimitKey(address asset) external pure returns (bytes32 key);

    function psm3_getWithdrawRateLimitKey(address asset) external pure returns (bytes32 key);

    /**********************************************************************************************/
    /*** SparkVaultFacet actions                                                                ***/
    /**********************************************************************************************/

    function sparkVault_VERSION() external pure returns (string memory);

    function sparkVault_take(address sparkVault, uint256 assetAmount) external;

    function sparkVault_getTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

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

    function uniswapV3_getMaxSlippage(address pool) external view returns (uint256);

    function uniswapV3_getMaxTickDelta(address pool) external view returns (uint24);

    function uniswapV3_getLiquidityTickBounds(address pool)
        external
        view
        returns (int24 lower, int24 upper);

    function uniswapV3_getTWAPSecondsAgo(address pool) external view returns (uint32);

    function uniswapV3_getAggregateDepositRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getAssetDepositRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getSwapRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getAggregateWithdrawRateLimitKey(address pool)
        external
        pure
        returns (bytes32 key);

    function uniswapV3_getAssetWithdrawRateLimitKey(address pool, address token)
        external
        pure
        returns (bytes32 key);

}
