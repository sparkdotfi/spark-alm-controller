// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { CentrifugeLib }    from "./libraries/CentrifugeLib.sol";
import { CurveLib }         from "./libraries/CurveLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { ERC7540Lib }       from "./libraries/ERC7540Lib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { MerklLib }         from "./libraries/MerklLib.sol";
import { OTCLib }           from "./libraries/OTCLib.sol";
import { PendleLib }        from "./libraries/PendleLib.sol";
import { PSMLib }           from "./libraries/PSMLib.sol";
import { UniswapV3Lib }     from "./libraries/UniswapV3Lib.sol";
import { UniswapV4Lib }     from "./libraries/UniswapV4Lib.sol";

import { Controller } from "./Controller.sol";

interface IDaiUsdsLike {

    function dai() external view returns (address);

}

interface IPSMLike {

    function gem() external view returns (address);

}

interface IVaultLike {

    function buffer() external view returns (address);
}

contract MainnetController is Controller, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CCTPMaxFeeCapSet(uint256 maxFeeCap);

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    event PendleRouterSet(address indexed pendleRouter);

    event MerklDistributorSet(address indexed merklDistributor);

    event UniswapV3SwapRouterSet(address indexed swapRouter);

    event UniswapV3PositionManagerSet(address indexed manager);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public FREEZER = keccak256("FREEZER");
    bytes32 public RELAYER = keccak256("RELAYER");

    bytes32 public LIMIT_4626_DEPOSIT            = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_4626_WITHDRAW           = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_7540_DEPOSIT            = ERC7540Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_7540_REDEEM             = ERC7540Lib.LIMIT_REDEEM;
    bytes32 public LIMIT_AAVE_DEPOSIT            = AaveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_AAVE_WITHDRAW           = AaveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_CENTRIFUGE_TRANSFER     = CentrifugeLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_CURVE_DEPOSIT           = CurveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_CURVE_SWAP              = CurveLib.LIMIT_SWAP;
    bytes32 public LIMIT_CURVE_WITHDRAW          = CurveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_LAYERZERO_TRANSFER      = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_OTC_SWAP                = OTCLib.LIMIT_SWAP;
    bytes32 public LIMIT_UNISWAP_V3_DEPOSIT      = UniswapV3Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V3_SWAP         = UniswapV3Lib.LIMIT_SWAP;
    bytes32 public LIMIT_UNISWAP_V3_WITHDRAW     = UniswapV3Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_DEPOSIT      = UniswapV4Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V4_WITHDRAW     = UniswapV4Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_SWAP         = UniswapV4Lib.LIMIT_SWAP;
    bytes32 public LIMIT_USDC_TO_CCTP            = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public LIMIT_USDC_TO_DOMAIN          = CCTPLib.LIMIT_TO_DOMAIN;
    bytes32 public LIMIT_USDS_TO_USDC            = PSMLib.LIMIT_USDS_TO_USDC;
    bytes32 public LIMIT_PENDLE_PT_REDEEM        = PendleLib.LIMIT_REDEEM;

    address public buffer;

    IALMProxy   public proxy;
    address     public cctp;
    address     public daiUsds;
    address     public ethenaMinter;
    address     public psm;
    IRateLimits public rateLimits;
    address     public vault;

    address public dai;
    address public usds;
    address public usde;
    address public usdc;
    address public ustb;
    address public susde;
    address public pendleRouter;
    address public merklDistributor;

    address public uniswapV3PositionManager;
    address public uniswapV3Router;

    // NOTE : Nominal maxFee cap for all cctp supported domains
    uint256 public cctpMaxFeeCap;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain       => bytes32 mintRecipient)       public mintRecipients;  // CCTP mint recipients
    mapping(uint32 destinationEndpointId   => bytes32 layerZeroRecipient)  public layerZeroRecipients;
    mapping(uint16 destinationCentrifugeId => bytes32 centrifugeRecipient) public centrifugeRecipients;

    // OTC swap (also uses maxSlippages)
    mapping(address exchange => OTCLib.OTC otcData) public otcs;

    mapping(address exchange => mapping(address asset => bool)) public otcWhitelistedAssets;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

    // Uniswap V3 pool params
    mapping(address pool => UniswapV3Lib.PoolParams params) public uniswapV3PoolParams;

    // Uniswap V4 tick ranges
    mapping(bytes32 poolId => UniswapV4Lib.TickLimits tickLimits) public uniswapV4TickLimits;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address accessControls_,
        address parameters_,
        address vault_,
        address psm_,
        address daiUsds_,
        address cctp_
    ) Controller(accessControls_, parameters_, proxy_, rateLimits_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = IALMProxy(proxy_);
        rateLimits = IRateLimits(rateLimits_);
        vault      = vault_;
        buffer     = IVaultLike(vault_).buffer();
        psm        = psm_;
        daiUsds    = daiUsds_;
        cctp       = cctp_;

        ethenaMinter = Ethereum.ETHENA_MINTER;

        susde = Ethereum.SUSDE;
        ustb  = Ethereum.USTB;
        dai   = IDaiUsdsLike(daiUsds).dai();
        usdc  = IPSMLike(psm).gem();
        usds  = Ethereum.USDS;
        usde  = Ethereum.USDE;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setCCTPMaxFeeCap(uint256 maxFeeCap)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPMaxFeeCapSet(cctpMaxFeeCap = maxFeeCap);
    }

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CCTPLib.setMintRecipient(mintRecipients, recipient, destinationDomain);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LayerZeroLib.setRecipient(layerZeroRecipients, destinationEndpointId, recipient);
    }

    function setMerklDistributor(address merklDistributor_)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        merklDistributor = merklDistributor_;
        emit MerklDistributorSet(merklDistributor_);
    }

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "MC/pool-zero-address");

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

    function setPendleRouter(address pendleRouter_)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        pendleRouter = pendleRouter_;
        emit PendleRouterSet(pendleRouter_);
    }

    function setOTCBuffer(address exchange, address otcBuffer)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setBuffer(exchange, otcBuffer, otcs, maxSlippages);
    }

    function setOTCRechargeRate(address exchange, uint256 rechargeRate18)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setRechargeRate(exchange, rechargeRate18, otcs);
    }

    function setOTCWhitelistedAsset(address exchange, address asset, bool isWhitelisted)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        OTCLib.setWhitelistedAsset(exchange, asset, isWhitelisted, otcWhitelistedAssets, otcs);
    }

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ERC4626Lib.setMaxExchangeRate(maxExchangeRates, token, shares, maxExpectedAssets);
    }

    function setUniswapV3PositionManager(address manager)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3PositionManagerSet(uniswapV3PositionManager = manager);
    }

    function setUniswapV3SwapRouter(address swapRouter)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3SwapRouterSet(uniswapV3Router = swapRouter);
    }

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setPoolMaxTickDelta(pool, maxTickDelta, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityLowerTickBound(pool, lowerTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityUpperTickBound(pool, upperTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3TWAPSecondsAgo(address pool, uint32 twapSecondsAgo)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setTWAPSecondsAgo(pool, twapSecondsAgo, uniswapV3PoolParams);
    }

    function setUniswapV4TickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV4Lib.setTickLimits(
            poolId,
            tickLowerMin,
            tickUpperMax,
            maxTickSpacing,
            uniswapV4TickLimits
        );
    }

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CentrifugeLib.setCentrifugeRecipient(centrifugeRecipients, centrifugeId, recipient);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return ERC4626Lib.deposit({
            proxy            : address(proxy),
            rateLimits       : address(rateLimits),
            token            : token,
            amount           : amount,
            minSharesOut     : minSharesOut,
            maxExchangeRates : maxExchangeRates
        });
    }

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return ERC4626Lib.withdraw(address(proxy), address(rateLimits), token, amount, maxSharesIn);
    }

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 assets)
    {
        return ERC4626Lib.redeem(address(proxy), address(rateLimits), token, shares, minAssetsOut);
    }

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256) {
        return ERC4626Lib.EXCHANGE_RATE_PRECISION;
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external nonReentrant onlyRole(RELAYER) {
        AaveLib.deposit(address(proxy), address(rateLimits), aToken, amount, maxSlippages);
    }

    function withdrawAave(address aToken, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountWithdrawn)
    {
        return AaveLib.withdraw(address(proxy), address(rateLimits), aToken, amount);
    }

    /**********************************************************************************************/
    /*** Relayer Curve StableSwap functions                                                     ***/
    /**********************************************************************************************/

    function swapCurve(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return CurveLib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            pool         : pool,
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            maxSlippages : maxSlippages
        });
    }

    function addLiquidityCurve(address pool, uint256[] memory depositAmounts, uint256 minLpAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return CurveLib.addLiquidity({
            proxy          : address(proxy),
            rateLimits     : address(rateLimits),
            pool           : pool,
            minLpAmount    : minLpAmount,
            depositAmounts : depositAmounts,
            maxSlippages   : maxSlippages
        });
    }

    function removeLiquidityCurve(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256[] memory withdrawnTokens)
    {
        return CurveLib.removeLiquidity({
            proxy              : address(proxy),
            rateLimits         : address(rateLimits),
            pool               : pool,
            lpBurnAmount       : lpBurnAmount,
            minWithdrawAmounts : minWithdrawAmounts,
            maxSlippages       : maxSlippages
        });
    }

    /**********************************************************************************************/
    /*** Relayer UniswapV3 functions                                                            ***/
    /**********************************************************************************************/

    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  maxTickDelta
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return UniswapV3Lib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            pool         : pool,
            router       : uniswapV3Router,
            tokenIn      : tokenIn,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            tickDelta    : maxTickDelta,
            poolParams   : uniswapV3PoolParams
        });
    }

    function addLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        UniswapV3Lib.Ticks        calldata ticks,
        UniswapV3Lib.TokenAmounts calldata target,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 tokenId_, uint128 liquidity_, UniswapV3Lib.TokenAmounts memory amounts_)
    {
        ( tokenId_, liquidity_, amounts_ ) = UniswapV3Lib.addLiquidity({
            proxy           : address(proxy),
            rateLimits      : address(rateLimits),
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            ticks           : ticks,
            target          : target,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages,
            poolParams      : uniswapV3PoolParams
        });
    }

    function removeLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        uint128                            liquidity,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (UniswapV3Lib.TokenAmounts memory amounts_)
    {
        return UniswapV3Lib.removeLiquidity({
            proxy           : address(proxy),
            rateLimits      : address(rateLimits),
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            liquidity       : liquidity,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages
        });
    }

    /**********************************************************************************************/
    /*** Uniswap V4 functions                                                                   ***/
    /**********************************************************************************************/

    function mintPositionUniswapV4(
        bytes32 poolId,
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.mintPosition({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            poolId     : poolId,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : amount0Max,
            amount1Max : amount1Max,
            tickLimits : uniswapV4TickLimits
        });
    }

    function increaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.increasePosition({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            poolId            : poolId,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max,
            tickLimits        : uniswapV4TickLimits
        });
    }

    function decreaseLiquidityUniswapV4(
        bytes32 poolId,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint128 amount0Min,
        uint128 amount1Min
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.decreasePosition({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            poolId            : poolId,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });
    }

    function swapUniswapV4(
        bytes32 poolId,
        address tokenIn,
        uint128 amountIn,
        uint128 amountOutMin
    )
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        UniswapV4Lib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            poolId       : poolId,
            tokenIn      : tokenIn,
            amountIn     : amountIn,
            amountOutMin : amountOutMin,
            maxSlippages : maxSlippages
        });
    }

    /**********************************************************************************************/
    /*** Relayer Pendle functions                                                               ***/
    /**********************************************************************************************/

    function redeemPendlePT(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        PendleLib.redeem({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            market       : pendleMarket,
            router       : pendleRouter,
            pyAmountIn   : pyAmountIn,
            minAmountOut : minAmountOut
        });
    }

    /**********************************************************************************************/
    /*** Relayer Merkl functions                                                                ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address operator)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MerklLib.toggleOperator({
            proxy       : address(proxy),
            distributor : merklDistributor,
            operator    : operator
        });
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    function swapUSDSToUSDC(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        PSMLib.swapUSDSToUSDC({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            daiUSDS    : daiUsds,
            psm        : psm,
            usds       : usds,
            dai        : dai,
            usdcAmount : usdcAmount
        });
    }

    function swapUSDCToUSDS(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        PSMLib.swapUSDCToUSDS({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            daiUSDS    : daiUsds,
            psm        : psm,
            dai        : dai,
            usdc       : usdc,
            usdcAmount : usdcAmount
        });
    }

    function psmTo18ConversionFactor() external view returns (uint256) {
        return PSMLib.to18ConversionFactor(psm);
    }

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    function transferTokenLayerZero(
        address oftAddress,
        uint256 amount,
        uint32  destinationEndpointId
    )
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        LayerZeroLib.transfer({
            proxy                 : address(proxy),
            rateLimits            : address(rateLimits),
            oftAddress            : oftAddress,
            amount                : amount,
            destinationEndpointId : destinationEndpointId,
            layerZeroRecipients   : layerZeroRecipients
        });
    }

    /**********************************************************************************************/
    /*** Relayer bridging functions                                                             ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CCTPLib.transfer({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            cctp              : cctp,
            usdc              : usdc,
            destinationDomain : destinationDomain,
            usdcAmount        : usdcAmount,
            maxFee            : CCTPLib.MAX_FEE,
            cctpMaxFeeCap     : cctpMaxFeeCap,
            mintRecipients    : mintRecipients
        });
    }

    function transferUSDCToCCTP(uint256 usdcAmount, uint256 maxFee, uint32 destinationDomain)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CCTPLib.transfer({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            cctp              : cctp,
            usdc              : usdc,
            destinationDomain : destinationDomain,
            usdcAmount        : usdcAmount,
            maxFee            : maxFee,
            cctpMaxFeeCap     : cctpMaxFeeCap,
            mintRecipients    : mintRecipients
        });
    }

    /**********************************************************************************************/
    /*** OTC swap functions                                                                     ***/
    /**********************************************************************************************/

    function otcSend(address exchange, address assetToSend, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        OTCLib.send({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            exchange          : exchange,
            assetToSend       : assetToSend,
            amount            : amount,
            whitelistedAssets : otcWhitelistedAssets,
            otcs              : otcs,
            maxSlippages      : maxSlippages
        });
    }

    function otcClaim(address exchange, address assetToClaim)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        OTCLib.claim({
            proxy             : address(proxy),
            exchange          : exchange,
            assetToClaim      : assetToClaim,
            whitelistedAssets : otcWhitelistedAssets,
            otcs              : otcs
        });
    }

    function getOtcClaimWithRecharge(address exchange) external view returns (uint256) {
        return OTCLib.getClaimWithRecharge(exchange, otcs);
    }

    function isOtcSwapReady(address exchange) external view returns (bool) {
        return OTCLib.isSwapReady(exchange, otcs, maxSlippages);
    }

    /**********************************************************************************************/
    /*** Relayer ERC7540 functions                                                              ***/
    /**********************************************************************************************/

    function requestDepositERC7540(address token, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        ERC7540Lib.requestDeposit(address(proxy), address(rateLimits), token, amount);
    }

    function claimDepositERC7540(address token) external nonReentrant onlyRole(RELAYER) {
        ERC7540Lib.claimDeposit(address(proxy), address(rateLimits), token);
    }

    function requestRedeemERC7540(address token, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        ERC7540Lib.requestRedeem(address(proxy), address(rateLimits), token, shares);
    }

    function claimRedeemERC7540(address token) external nonReentrant onlyRole(RELAYER) {
        ERC7540Lib.claimRedeem(address(proxy), address(rateLimits), token);
    }

    /**********************************************************************************************/
    /*** Relayer Centrifuge functions                                                           ***/
    /**********************************************************************************************/

    // NOTE: These cancellation methods are compatible with ERC-7887

    function cancelCentrifugeDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelDepositRequest(address(proxy), address(rateLimits), token);
    }

    function claimCentrifugeCancelDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelDepositRequest(address(proxy), address(rateLimits), token);
    }

    function cancelCentrifugeRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelRedeemRequest(address(proxy), address(rateLimits), token);
    }

    function claimCentrifugeCancelRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelRedeemRequest(address(proxy), address(rateLimits), token);
    }

    function transferSharesCentrifuge(
        address token,
        uint128 amount,
        uint16  centrifugeId
    )
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.transferShares({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            token        : token,
            centrifugeId : centrifugeId,
            amount       : amount,
            recipients   : centrifugeRecipients
        });
    }

}
