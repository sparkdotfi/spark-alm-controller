// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { ReentrancyGuard }         from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { ApproveLib }       from "./libraries/ApproveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { CurveLib }         from "./libraries/CurveLib.sol";
import { DAIUSDSLib }       from "./libraries/DAIUSDSLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { FarmLib }          from "./libraries/FarmLib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { MapleLib }         from "./libraries/MapleLib.sol";
import { OTCLib }           from "./libraries/OTCLib.sol";
import { PSMLib }           from "./libraries/PSMLib.sol";
import { SparkVaultLib }    from "./libraries/SparkVaultLib.sol";
import { SuperstateLib }    from "./libraries/SuperstateLib.sol";
import { TransferAssetLib } from "./libraries/TransferAssetLib.sol";
import { UniswapV4Lib }     from "./libraries/UniswapV4Lib.sol";
import { USDELib }          from "./libraries/USDELib.sol";
import { USDSLib }          from "./libraries/USDSLib.sol";
import { WEETHLib }         from "./libraries/WEETHLib.sol";
import { WSTETHLib }        from "./libraries/WSTETHLib.sol";

interface IDAIUSDSLike {

    function dai() external view returns (address);

}

interface IPSMLike {

    function gem() external view returns (address);

}

interface IVaultLike {

    function buffer() external view returns (address);
}

contract MainnetController is ReentrancyGuard, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public FREEZER = keccak256("FREEZER");
    bytes32 public RELAYER = keccak256("RELAYER");

    bytes32 public LIMIT_4626_DEPOSIT            = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_4626_WITHDRAW           = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_AAVE_DEPOSIT            = AaveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_AAVE_WITHDRAW           = AaveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_ASSET_TRANSFER          = TransferAssetLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_CURVE_DEPOSIT           = CurveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_CURVE_SWAP              = CurveLib.LIMIT_SWAP;
    bytes32 public LIMIT_CURVE_WITHDRAW          = CurveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_FARM_DEPOSIT            = FarmLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_FARM_WITHDRAW           = FarmLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_LAYERZERO_TRANSFER      = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_MAPLE_REDEEM            = MapleLib.LIMIT_REDEEM;
    bytes32 public LIMIT_OTC_SWAP                = OTCLib.LIMIT_SWAP;
    bytes32 public LIMIT_SPARK_VAULT_TAKE        = SparkVaultLib.LIMIT_TAKE;
    bytes32 public LIMIT_SUPERSTATE_SUBSCRIBE    = SuperstateLib.LIMIT_SUBSCRIBE;
    bytes32 public LIMIT_SUSDE_COOLDOWN          = USDELib.LIMIT_SUSDE_COOLDOWN;
    bytes32 public LIMIT_UNISWAP_V4_DEPOSIT      = UniswapV4Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V4_WITHDRAW     = UniswapV4Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_SWAP         = UniswapV4Lib.LIMIT_SWAP;
    bytes32 public LIMIT_USDC_TO_CCTP            = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public LIMIT_USDC_TO_DOMAIN          = CCTPLib.LIMIT_TO_DOMAIN;
    bytes32 public LIMIT_USDE_BURN               = USDELib.LIMIT_USDE_BURN;
    bytes32 public LIMIT_USDE_MINT               = USDELib.LIMIT_USDE_MINT;
    bytes32 public LIMIT_USDS_MINT               = USDSLib.LIMIT_MINT;
    bytes32 public LIMIT_USDS_TO_USDC            = PSMLib.LIMIT_USDS_TO_USDC;
    bytes32 public LIMIT_WEETH_CLAIM_WITHDRAW    = WEETHLib.LIMIT_CLAIM_WITHDRAW;
    bytes32 public LIMIT_WEETH_DEPOSIT           = WEETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WEETH_REQUEST_WITHDRAW  = WEETHLib.LIMIT_REQUEST_WITHDRAW;
    bytes32 public LIMIT_WSTETH_DEPOSIT          = WSTETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WSTETH_REQUEST_WITHDRAW = WSTETHLib.LIMIT_REQUEST_WITHDRAW;

    address public buffer;  // Allocator buffer

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

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;  // CCTP mint recipients
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;

    // OTC swap (also uses maxSlippages)
    mapping(address exchange => OTCLib.OTC otcData) public otcs;

    mapping(address exchange => mapping(address asset => bool)) public otcWhitelistedAssets;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

    // Uniswap V4 tick ranges
    mapping(bytes32 poolId => UniswapV4Lib.TickLimits tickLimits) public uniswapV4TickLimits;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address vault_,
        address psm_,
        address daiUsds_,
        address cctp_
    ) {
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
        dai   = IDAIUSDSLike(daiUsds).dai();
        usdc  = IPSMLike(psm).gem();
        usds  = Ethereum.USDS;
        usde  = Ethereum.USDE;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CCTPLib.setMintRecipient(mintRecipients, recipient, destinationDomain);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 layerZeroRecipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LayerZeroLib.setLayerZeroRecipient(
            layerZeroRecipients,
            destinationEndpointId,
            layerZeroRecipient
        );
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
        UniswapV4Lib.setUniswapV4TickLimits(
            poolId,
            tickLowerMin,
            tickUpperMax,
            maxTickSpacing,
            uniswapV4TickLimits
        );
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer vault functions                                                                ***/
    /**********************************************************************************************/

    function mintUSDS(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        USDSLib.mint(address(proxy), address(rateLimits), vault, usds, usdsAmount);
    }

    function burnUSDS(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        USDSLib.burn(address(proxy), address(rateLimits), vault, usds, usdsAmount);
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        TransferAssetLib.transfer(address(proxy), address(rateLimits), asset, destination, amount);
    }

    /**********************************************************************************************/
    /*** wstETH Integration                                                                     ***/
    /**********************************************************************************************/

    function depositToWSTETH(uint256 amount) external nonReentrant onlyRole(RELAYER) {
        WSTETHLib.deposit({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            weth       : Ethereum.WETH,
            wsteth     : Ethereum.WSTETH,
            amount     : amount
        });
    }

    function requestWithdrawFromWSTETH(uint256 amountToRedeem)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256[] memory requestIds)
    {
        return WSTETHLib.requestWithdraw({
            proxy          : address(proxy),
            rateLimits     : address(rateLimits),
            wsteth         : Ethereum.WSTETH,
            withdrawQueue  : Ethereum.WSTETH_WITHDRAW_QUEUE,
            amountToRedeem : amountToRedeem
        });
    }

    function claimWithdrawalFromWSTETH(uint256 requestId) external nonReentrant onlyRole(RELAYER) {
        WSTETHLib.claimWithdrawal({
            proxy         : address(proxy),
            withdrawQueue : Ethereum.WSTETH_WITHDRAW_QUEUE,
            weth          : Ethereum.WETH,
            requestId     : requestId
        });
    }

    /**********************************************************************************************/
    /*** weETH Integration                                                                      ***/
    /**********************************************************************************************/

    function depositToWEETH(uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return WEETHLib.deposit(address(proxy), address(rateLimits), amount, minSharesOut);
    }

    function requestWithdrawFromWEETH(address weethModule, uint256 weethShares)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 requestId)
    {
        return WEETHLib.requestWithdraw(
            address(proxy),
            address(rateLimits),
            weethShares,
            weethModule
        );
    }

    function claimWithdrawalFromWEETH(address weethModule, uint256 requestId)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 ethReceived)
    {
        return WEETHLib.claimWithdrawal(
            address(proxy),
            address(rateLimits),
            requestId,
            weethModule
        );
    }

    /**********************************************************************************************/
    /*** Relayer wrap ETH function                                                              ***/
    /**********************************************************************************************/

    function wrapAllProxyETH() external nonReentrant onlyRole(RELAYER) {
        uint256 proxyBalance = address(proxy).balance;

        if (proxyBalance == 0) return;

        proxy.doCallWithValue(
            Ethereum.WETH,
            "",
            proxyBalance
        );
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
            token            : token,
            amount           : amount,
            minSharesOut     : minSharesOut,
            maxExchangeRates : maxExchangeRates,
            rateLimits       : address(rateLimits)
        });
    }

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return ERC4626Lib.withdraw(address(proxy), token, amount, maxSharesIn, address(rateLimits));
    }

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 assets)
    {
        return ERC4626Lib.redeem(address(proxy), token, shares, minAssetsOut, address(rateLimits));
    }

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256) {
        return ERC4626Lib.EXCHANGE_RATE_PRECISION;
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external nonReentrant onlyRole(RELAYER) {
        AaveLib.deposit(address(proxy), aToken, amount, maxSlippages[aToken], address(rateLimits));
    }

    function withdrawAave(address aToken, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountWithdrawn)
    {
        return AaveLib.withdraw(address(proxy), aToken, amount, address(rateLimits));
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
        uint256 maxSlippage = maxSlippages[pool];

        return CurveLib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            pool         : pool,
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            maxSlippage  : maxSlippage
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
            maxSlippage    : maxSlippages[pool],
            depositAmounts : depositAmounts
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
            maxSlippage        : maxSlippages[pool]
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
            maxSlippage  : maxSlippages[address(uint160(uint256(poolId)))]
        });
    }

    /**********************************************************************************************/
    /*** Relayer Ethena functions                                                               ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner) external nonReentrant onlyRole(RELAYER) {
        USDELib.setDelegatedSigner(address(proxy), ethenaMinter, delegatedSigner);
    }

    function removeDelegatedSigner(address delegatedSigner)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        USDELib.removeDelegatedSigner(address(proxy), ethenaMinter, delegatedSigner);
    }

    // Note that Ethena's mint/redeem per-block limits include other users.
    function prepareUSDEMint(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        USDELib.prepareUSDEMint({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            usdc       : usdc,
            minter     : ethenaMinter,
            usdcAmount : usdcAmount
        });
    }

    function prepareUSDEBurn(uint256 usdeAmount) external nonReentrant onlyRole(RELAYER) {
        USDELib.prepareUSDEBurn({
            proxy      : address(proxy),
            rateLimits : address(rateLimits),
            usde       : address(usde),
            minter     : ethenaMinter,
            usdeAmount : usdeAmount
        });
    }

    function cooldownAssetsSUSDE(uint256 usdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownShares)
    {
        return USDELib.cooldownAssetsSUSDE(address(proxy), address(rateLimits), susde, usdeAmount);
    }

    function cooldownSharesSUSDE(uint256 susdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownAssets)
    {
        return USDELib.cooldownSharesSUSDE(address(proxy), address(rateLimits), susde, susdeAmount);
    }

    function unstakeSUSDE() external nonReentrant onlyRole(RELAYER) {
        USDELib.unstakeSUSDE(address(proxy), address(susde));
    }

    /**********************************************************************************************/
    /*** Relayer Maple functions                                                                ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MapleLib.requestRedemption(address(proxy), address(rateLimits), mapleToken, shares);
    }

    function cancelMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        MapleLib.cancelRedemption(address(proxy), address(rateLimits), mapleToken, shares);
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        SuperstateLib.subscribe(address(proxy), address(rateLimits), usdc, ustb, usdcAmount);
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        DAIUSDSLib.swapUSDSToDAI(address(proxy), address(usds), address(daiUsds), usdsAmount);
    }

    function swapDAIToUSDS(uint256 daiAmount) external nonReentrant onlyRole(RELAYER) {
        DAIUSDSLib.swapDAIToUSDS(address(proxy), address(dai), address(daiUsds), daiAmount);
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
        LayerZeroLib.transferTokenLayerZero({
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
        CCTPLib.transferUSDCToCCTP({
            proxy             : address(proxy),
            rateLimits        : address(rateLimits),
            cctp              : cctp,
            usdc              : usdc,
            mintRecipient     : mintRecipients[destinationDomain],
            destinationDomain : destinationDomain,
            usdcAmount        : usdcAmount
        });
    }

    /**********************************************************************************************/
    /*** Relayer SPK Farm functions                                                             ***/
    /**********************************************************************************************/

    function depositToFarm(address farm, uint256 amount) external nonReentrant onlyRole(RELAYER) {
        FarmLib.deposit(address(proxy), address(rateLimits), address(usds), farm, amount);
    }

    function withdrawFromFarm(address farm, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        FarmLib.withdraw(address(proxy), address(rateLimits), farm, amount);
    }

    /**********************************************************************************************/
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        SparkVaultLib.take(address(proxy), address(rateLimits), sparkVault, assetAmount);
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

    function getOTCClaimWithRecharge(address exchange) external view returns (uint256) {
        return OTCLib.getClaimWithRecharge(exchange, otcs);
    }

    function isOTCSwapReady(address exchange) external view returns (bool) {
        return OTCLib.isSwapReady(exchange, otcs, maxSlippages);
    }

}
