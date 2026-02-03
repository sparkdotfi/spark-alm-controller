// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { ReentrancyGuard }         from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IERC20 }         from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 }       from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { AaveLib }      from "./libraries/AaveLib.sol";
import { ApproveLib }   from "./libraries/ApproveLib.sol";
import { CCTPLib }      from "./libraries/CCTPLib.sol";
import { CurveLib }     from "./libraries/CurveLib.sol";
import { ERC4626Lib }   from "./libraries/ERC4626Lib.sol";
import { LayerZeroLib } from "./libraries/LayerZeroLib.sol";
import { PSMLib }       from "./libraries/PSMLib.sol";
import { UniswapV4Lib } from "./libraries/UniswapV4Lib.sol";
import { USDSLib }      from "./libraries/USDSLib.sol";
import { WEETHLib }     from "./libraries/WEETHLib.sol";
import { WSTETHLib }    from "./libraries/WSTETHLib.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IDaiUsdsLike {

    function dai() external view returns (address);

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

interface IPSMLike {

    function gem() external view returns (address);

}

interface IEthenaMinterLike {

    function setDelegatedSigner(address delegateSigner) external;

    function removeDelegatedSigner(address delegateSigner) external;

}

interface IFarmLike {

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

}

interface IMapleTokenLike is IERC4626 {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

}

interface ISparkVaultLike {

    function take(uint256 assetAmount) external;

}

interface ISUSDELike is IERC4626 {

    function cooldownAssets(uint256 usdeAmount) external returns (uint256);

    function cooldownShares(uint256 susdeAmount) external returns (uint256);

    function unstake(address receiver) external;

}

interface IUSTBLike is IERC20 {

    function subscribe(uint256 inAmount, address stablecoin) external;

}

interface IVaultLike {

    function buffer() external view returns (address);
}

contract MainnetController is ReentrancyGuard, AccessControlEnumerable {

    struct OTC {
        address buffer;
        uint256 rechargeRate18;
        uint256 sent18;
        uint256 sentTimestamp;
        uint256 claimed18;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event OTCBufferSet(
        address indexed exchange,
        address indexed oldOTCBuffer,
        address indexed newOTCBuffer
    );

    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed assetClaimed,
        uint256         amountClaimed,
        uint256         amountClaimed18
    );

    event OTCRechargeRateSet(address indexed exchange, uint256 oldRate18, uint256 newRate18);

    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256         amountSent,
        uint256         amountSent18
    );

    event OTCWhitelistedAssetSet(
        address indexed exchange,
        address indexed asset,
        bool            isWhitelisted
    );

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
    bytes32 public LIMIT_ASSET_TRANSFER          = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public LIMIT_CURVE_DEPOSIT           = CurveLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_CURVE_SWAP              = CurveLib.LIMIT_SWAP;
    bytes32 public LIMIT_CURVE_WITHDRAW          = CurveLib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_FARM_DEPOSIT            = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public LIMIT_FARM_WITHDRAW           = keccak256("LIMIT_FARM_WITHDRAW");
    bytes32 public LIMIT_LAYERZERO_TRANSFER      = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public LIMIT_MAPLE_REDEEM            = keccak256("LIMIT_MAPLE_REDEEM");
    bytes32 public LIMIT_OTC_SWAP                = keccak256("LIMIT_OTC_SWAP");
    bytes32 public LIMIT_SPARK_VAULT_TAKE        = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 public LIMIT_SUPERSTATE_SUBSCRIBE    = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");
    bytes32 public LIMIT_SUSDE_COOLDOWN          = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 public LIMIT_UNISWAP_V4_DEPOSIT      = UniswapV4Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V4_WITHDRAW     = UniswapV4Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_SWAP         = UniswapV4Lib.LIMIT_SWAP;
    bytes32 public LIMIT_USDC_TO_CCTP            = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public LIMIT_USDC_TO_DOMAIN          = CCTPLib.LIMIT_TO_DOMAIN;
    bytes32 public LIMIT_USDE_BURN               = keccak256("LIMIT_USDE_BURN");
    bytes32 public LIMIT_USDE_MINT               = keccak256("LIMIT_USDE_MINT");
    bytes32 public LIMIT_USDS_MINT               = USDSLib.LIMIT_MINT;
    bytes32 public LIMIT_USDS_TO_USDC            = PSMLib.LIMIT_USDS_TO_USDC;
    bytes32 public LIMIT_WEETH_CLAIM_WITHDRAW    = WEETHLib.LIMIT_CLAIM_WITHDRAW;
    bytes32 public LIMIT_WEETH_DEPOSIT           = WEETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WEETH_REQUEST_WITHDRAW  = WEETHLib.LIMIT_REQUEST_WITHDRAW;
    bytes32 public LIMIT_WSTETH_DEPOSIT          = WSTETHLib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_WSTETH_REQUEST_WITHDRAW = WSTETHLib.LIMIT_REQUEST_WITHDRAW;

    address public buffer;  // Allocator buffer

    IALMProxy         public proxy;
    address           public cctp;
    address           public daiUsds;
    IEthenaMinterLike public ethenaMinter;
    address           public psm;
    IRateLimits       public rateLimits;
    address           public vault;

    address    public dai;
    address    public usds;
    address    public usde;
    address    public usdc;
    IUSTBLike  public ustb;
    ISUSDELike public susde;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;  // CCTP mint recipients
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;

    // OTC swap (also uses maxSlippages)
    mapping(address exchange => OTC otcData) public otcs;

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

        ethenaMinter = IEthenaMinterLike(Ethereum.ETHENA_MINTER);

        susde = ISUSDELike(Ethereum.SUSDE);
        ustb  = IUSTBLike(Ethereum.USTB);
        dai   = IDaiUsdsLike(daiUsds).dai();
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
        require(exchange  != address(0), "MC/exchange-zero-address");
        require(otcBuffer != address(0), "MC/otcBuffer-zero-address");
        require(exchange  != otcBuffer,  "MC/exchange-equals-otcBuffer");

        OTC storage otc = otcs[exchange];

        // Prevent rotating buffer while a swap is pending and not ready
        require(otc.sentTimestamp == 0 || isOtcSwapReady(exchange), "MC/swap-in-progress");

        emit OTCBufferSet(exchange, otc.buffer, otcBuffer);
        otc.buffer = otcBuffer;
    }

    function setOTCRechargeRate(address exchange, uint256 rechargeRate18)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange != address(0), "MC/exchange-zero-address");

        OTC storage otc = otcs[exchange];

        emit OTCRechargeRateSet(exchange, otc.rechargeRate18, rechargeRate18);
        otc.rechargeRate18 = rechargeRate18;
    }

    function setOTCWhitelistedAsset(address exchange, address asset, bool isWhitelisted)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange              != address(0), "MC/exchange-zero-address");
        require(asset                 != address(0), "MC/asset-zero-address");
        require(otcs[exchange].buffer != address(0), "MC/otc-buffer-not-set");

        emit OTCWhitelistedAssetSet(exchange, asset, isWhitelisted);
        otcWhitelistedAssets[exchange][asset] = isWhitelisted;
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
        _rateLimited(
            RateLimitHelpers.makeAddressAddressKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        _transfer(asset, destination, amount);
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
        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.setDelegatedSigner, (address(delegatedSigner)))
        );
    }

    function removeDelegatedSigner(address delegatedSigner)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.removeDelegatedSigner, (address(delegatedSigner)))
        );
    }

    // Note that Ethena's mint/redeem per-block limits include other users
    function prepareUSDeMint(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        _rateLimited(LIMIT_USDE_MINT, usdcAmount);
        ApproveLib.approve(usdc, address(proxy), address(ethenaMinter), usdcAmount);
    }

    function prepareUSDeBurn(uint256 usdeAmount) external nonReentrant onlyRole(RELAYER) {
        _rateLimited(LIMIT_USDE_BURN, usdeAmount);
        ApproveLib.approve(usde, address(proxy), address(ethenaMinter), usdeAmount);
    }

    function cooldownAssetsSUSDe(uint256 usdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownShares)
    {
        _rateLimited(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        return abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function cooldownSharesSUSDe(uint256 susdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 cooldownAssets)
    {
        cooldownAssets = abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        _rateLimited(LIMIT_SUSDE_COOLDOWN, cooldownAssets);
    }

    function unstakeSUSDe() external nonReentrant onlyRole(RELAYER) {
        proxy.doCall(
            address(susde),
            abi.encodeCall(susde.unstake, (address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Maple functions                                                                ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        _rateLimitedAddress(
            LIMIT_MAPLE_REDEEM,
            mapleToken,
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        );

        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).requestRedeem, (shares, address(proxy)))
        );
    }

    function cancelMapleRedemption(address mapleToken, uint256 shares)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        _rateLimitExists(RateLimitHelpers.makeAddressKey(LIMIT_MAPLE_REDEEM, mapleToken));

        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).removeShares, (shares, address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER) {
        _rateLimited(LIMIT_SUPERSTATE_SUBSCRIBE, usdcAmount);

        ApproveLib.approve(usdc, address(proxy), address(ustb), usdcAmount);

        proxy.doCall(
            address(ustb),
            abi.encodeCall(ustb.subscribe, (usdcAmount, usdc))
        );
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        ApproveLib.approve(usds, address(proxy), daiUsds, usdsAmount);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            daiUsds,
            abi.encodeCall(IDaiUsdsLike.usdsToDai, (address(proxy), usdsAmount))
        );
    }

    function swapDAIToUSDS(uint256 daiAmount) external nonReentrant onlyRole(RELAYER) {
        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        ApproveLib.approve(dai, address(proxy), daiUsds, daiAmount);

        // Swap DAI to USDS 1:1
        proxy.doCall(
            daiUsds,
            abi.encodeCall(IDaiUsdsLike.daiToUsds, (address(proxy), daiAmount))
        );
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

    function depositToFarm(address farm, uint256 usdsAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        _rateLimited(
            keccak256(abi.encode(LIMIT_FARM_DEPOSIT, farm)),
            usdsAmount
        );

        ApproveLib.approve(usds, address(proxy), farm, usdsAmount);

        proxy.doCall(
            farm,
            abi.encodeCall(IFarmLike.stake, (usdsAmount))
        );
    }

    function withdrawFromFarm(address farm, uint256 usdsAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        _rateLimited(
            keccak256(abi.encode(LIMIT_FARM_WITHDRAW, farm)),
            usdsAmount
        );

        proxy.doCall(
            farm,
            abi.encodeCall(IFarmLike.withdraw, (usdsAmount))
        );
        proxy.doCall(
            farm,
            abi.encodeCall(IFarmLike.getReward, ())
        );
    }

    /**********************************************************************************************/
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        _rateLimitedAddress(LIMIT_SPARK_VAULT_TAKE, sparkVault, assetAmount);

        // Take assets from the vault
        proxy.doCall(
            sparkVault,
            abi.encodeCall(ISparkVaultLike.take, (assetAmount))
        );
    }

    /**********************************************************************************************/
    /*** OTC swap functions                                                                     ***/
    /**********************************************************************************************/

    function otcSend(address exchange, address assetToSend, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        require(assetToSend != address(0), "MC/asset-to-send-zero");
        require(amount > 0,                "MC/amount-to-send-zero");

        require(
            otcWhitelistedAssets[exchange][assetToSend],
            "MC/asset-not-whitelisted"
        );

        // NOTE: This will lose precision for tokens with >18 decimals.
        uint256 sent18 = amount * 1e18 / 10 ** IERC20Metadata(assetToSend).decimals();

        _rateLimitedAddress(LIMIT_OTC_SWAP, exchange, sent18);

        OTC storage otc = otcs[exchange];

        // Its impossible to have zero address buffer because of whitelistedAssets.
        require(isOtcSwapReady(exchange), "MC/last-swap-not-returned");

        otc.sent18        = sent18;
        otc.sentTimestamp = block.timestamp;
        otc.claimed18     = 0;

        // NOTE: Reentrancy not relevant here because there are no state changes after this call
        _transfer(assetToSend, exchange, amount);

        emit OTCSwapSent(exchange, otc.buffer, assetToSend, amount, sent18);
    }

    function otcClaim(address exchange, address assetToClaim)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        address otcBuffer = otcs[exchange].buffer;

        require(assetToClaim != address(0), "MC/asset-to-claim-zero");
        require(otcBuffer    != address(0), "MC/otc-buffer-not-set");

        require(
            otcWhitelistedAssets[exchange][assetToClaim],
            "MC/asset-not-whitelisted"
        );

        uint256 amountToClaim = IERC20(assetToClaim).balanceOf(otcBuffer);

        // NOTE: This will lose precision for tokens with >18 decimals.
        uint256 amountToClaim18
            = amountToClaim * 1e18 / 10 ** IERC20Metadata(assetToClaim).decimals();

        otcs[exchange].claimed18 += amountToClaim18;

        // Transfer assets from the OTC buffer to the proxy
        // NOTE: Reentrancy not possible here because both are known contracts.
        _transferFrom(assetToClaim, otcBuffer, address(proxy), amountToClaim);

        emit OTCClaimed(exchange, otcBuffer, assetToClaim, amountToClaim, amountToClaim18);
    }

    function getOtcClaimWithRecharge(address exchange) public view returns (uint256) {
        OTC memory otc = otcs[exchange];

        if (otc.sentTimestamp == 0) return 0;

        return otc.claimed18 + (block.timestamp - otc.sentTimestamp) * otc.rechargeRate18;
    }

    function isOtcSwapReady(address exchange) public view returns (bool) {
        // If maxSlippages is not set, the exchange is not onboarded.
        if (maxSlippages[exchange] == 0) return false;

        return getOtcClaimWithRecharge(exchange)
            >= otcs[exchange].sent18 * maxSlippages[exchange] / 1e18;
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    function _transfer(address asset, address destination, uint256 amount) internal {
        bytes memory returnData = proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "MC/transfer-failed"
        );
    }

    function _transferFrom(
        address asset,
        address source,
        address destination,
        uint256 amount
    )
        internal
    {
        bytes memory returnData = proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transferFrom, (source, destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "MC/transferFrom-failed"
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

    function _rateLimitedAddress(bytes32 key, address asset, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(RateLimitHelpers.makeAddressKey(key, asset), amount);
    }

    function _rateLimitExists(bytes32 key) internal view {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "MC/invalid-action"
        );
    }

}
