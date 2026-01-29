// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { ReentrancyGuard }         from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IERC20 }         from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 }       from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { ICCTPLike }   from "./interfaces/CCTPInterfaces.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { ApproveLib }                     from "./libraries/ApproveLib.sol";
import { AaveLib }                        from "./libraries/AaveLib.sol";
import { CCTPLib }                        from "./libraries/CCTPLib.sol";
import { CurveLib }                       from "./libraries/CurveLib.sol";
import { ERC4626Lib }                     from "./libraries/ERC4626Lib.sol";
import { LayerZeroLib }                   from "./libraries/LayerZeroLib.sol";
import { IDaiUsdsLike, IPSMLike, PSMLib } from "./libraries/PSMLib.sol";
import { UniswapV4Lib }                   from "./libraries/UniswapV4Lib.sol";
import { WEETHLib }                       from "./libraries/WEETHLib.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
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
    function draw(uint256 usdsAmount) external;
    function wipe(uint256 usdsAmount) external;
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

interface IWithdrawalQueue {
    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external returns (uint256[] memory requestIds);
    function claimWithdrawal(uint256 _requestId) external;
}

interface IWstETHLike {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
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

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);
    event MaxExchangeRateSet(address indexed token, uint256 maxExchangeRate);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
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
    event UniswapV4TickLimitsSet(
        bytes32 indexed poolId,
        int24           tickLowerMin,
        int24           tickUpperMax,
        uint24          maxTickSpacing
    );

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public FREEZER = keccak256("FREEZER");
    bytes32 public RELAYER = keccak256("RELAYER");

    bytes32 public LIMIT_4626_DEPOSIT            = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public LIMIT_4626_WITHDRAW           = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public LIMIT_AAVE_DEPOSIT            = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public LIMIT_AAVE_WITHDRAW           = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public LIMIT_ASSET_TRANSFER          = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public LIMIT_CURVE_DEPOSIT           = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public LIMIT_CURVE_SWAP              = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public LIMIT_CURVE_WITHDRAW          = keccak256("LIMIT_CURVE_WITHDRAW");
    bytes32 public LIMIT_FARM_DEPOSIT            = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public LIMIT_FARM_WITHDRAW           = keccak256("LIMIT_FARM_WITHDRAW");
    bytes32 public LIMIT_LAYERZERO_TRANSFER      = LayerZeroLib.LIMIT_LAYERZERO_TRANSFER;
    bytes32 public LIMIT_MAPLE_REDEEM            = keccak256("LIMIT_MAPLE_REDEEM");
    bytes32 public LIMIT_OTC_SWAP                = keccak256("LIMIT_OTC_SWAP");
    bytes32 public LIMIT_SPARK_VAULT_TAKE        = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 public LIMIT_SUPERSTATE_SUBSCRIBE    = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");
    bytes32 public LIMIT_SUSDE_COOLDOWN          = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 public LIMIT_UNISWAP_V4_DEPOSIT      = UniswapV4Lib.LIMIT_DEPOSIT;
    bytes32 public LIMIT_UNISWAP_V4_WITHDRAW     = UniswapV4Lib.LIMIT_WITHDRAW;
    bytes32 public LIMIT_UNISWAP_V4_SWAP         = UniswapV4Lib.LIMIT_SWAP;
    bytes32 public LIMIT_USDC_TO_CCTP            = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public LIMIT_USDC_TO_DOMAIN          = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 public LIMIT_USDE_BURN               = keccak256("LIMIT_USDE_BURN");
    bytes32 public LIMIT_USDE_MINT               = keccak256("LIMIT_USDE_MINT");
    bytes32 public LIMIT_USDS_MINT               = keccak256("LIMIT_USDS_MINT");
    bytes32 public LIMIT_USDS_TO_USDC            = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 public LIMIT_WEETH_CLAIM_WITHDRAW    = WEETHLib.LIMIT_WEETH_CLAIM_WITHDRAW;
    bytes32 public LIMIT_WEETH_DEPOSIT           = WEETHLib.LIMIT_WEETH_DEPOSIT;
    bytes32 public LIMIT_WEETH_REQUEST_WITHDRAW  = WEETHLib.LIMIT_WEETH_REQUEST_WITHDRAW;
    bytes32 public LIMIT_WSTETH_DEPOSIT          = keccak256("LIMIT_WSTETH_DEPOSIT");
    bytes32 public LIMIT_WSTETH_REQUEST_WITHDRAW = keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW");

    address public buffer;  // Allocator buffer

    IALMProxy         public proxy;
    ICCTPLike         public cctp;
    IDaiUsdsLike      public daiUsds;
    IEthenaMinterLike public ethenaMinter;
    IPSMLike          public psm;
    IRateLimits       public rateLimits;
    IVaultLike        public vault;

    IERC20     public dai;
    IERC20     public usds;
    IERC20     public usde;
    IERC20     public usdc;
    IUSTBLike  public ustb;
    ISUSDELike public susde;

    uint256 public psmTo18ConversionFactor;

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
        vault      = IVaultLike(vault_);
        buffer     = IVaultLike(vault_).buffer();
        psm        = IPSMLike(psm_);
        daiUsds    = IDaiUsdsLike(daiUsds_);
        cctp       = ICCTPLike(cctp_);

        ethenaMinter = IEthenaMinterLike(Ethereum.ETHENA_MINTER);

        susde = ISUSDELike(Ethereum.SUSDE);
        ustb  = IUSTBLike(Ethereum.USTB);
        dai   = IERC20(daiUsds.dai());
        usdc  = IERC20(psm.gem());
        usds  = IERC20(Ethereum.USDS);
        usde  = IERC20(Ethereum.USDE);

        psmTo18ConversionFactor = psm.to18ConversionFactor();
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMintRecipient(uint32 destinationDomain, bytes32 mintRecipient)
        external nonReentrant
    {
        _checkRole(DEFAULT_ADMIN_ROLE);
        mintRecipients[destinationDomain] = mintRecipient;
        emit MintRecipientSet(destinationDomain, mintRecipient);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 layerZeroRecipient)
        external nonReentrant
    {
        _checkRole(DEFAULT_ADMIN_ROLE);
        layerZeroRecipients[destinationEndpointId] = layerZeroRecipient;
        emit LayerZeroRecipientSet(destinationEndpointId, layerZeroRecipient);
    }

    function setMaxSlippage(address pool, uint256 maxSlippage) external nonReentrant {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(pool != address(0), "MC/pool-zero-address");

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

    function setOTCBuffer(address exchange, address otcBuffer) external nonReentrant {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(exchange  != address(0), "MC/exchange-zero-address");
        require(otcBuffer != address(0), "MC/otcBuffer-zero-address");
        require(exchange  != otcBuffer,  "MC/exchange-equals-otcBuffer");

        OTC storage otc = otcs[exchange];

        // Prevent rotating buffer while a swap is pending and not ready
        require(otc.sentTimestamp == 0 || isOtcSwapReady(exchange), "MC/swap-in-progress");

        emit OTCBufferSet(exchange, otc.buffer, otcBuffer);
        otc.buffer = otcBuffer;
    }

    function setOTCRechargeRate(address exchange, uint256 rechargeRate18) external nonReentrant {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(exchange != address(0), "MC/exchange-zero-address");

        OTC storage otc = otcs[exchange];

        emit OTCRechargeRateSet(exchange, otc.rechargeRate18, rechargeRate18);
        otc.rechargeRate18 = rechargeRate18;
    }

    function setOTCWhitelistedAsset(address exchange, address asset, bool isWhitelisted)
        external nonReentrant
    {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(exchange              != address(0), "MC/exchange-zero-address");
        require(asset                 != address(0), "MC/asset-zero-address");
        require(otcs[exchange].buffer != address(0), "MC/otc-buffer-not-set");

        emit OTCWhitelistedAssetSet(exchange, asset, isWhitelisted);
        otcWhitelistedAssets[exchange][asset] = isWhitelisted;
    }

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external nonReentrant
    {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(token != address(0), "MC/token-zero-address");

        emit MaxExchangeRateSet(
            token,
            maxExchangeRates[token] = ERC4626Lib.getExchangeRate(shares, maxExpectedAssets)
        );
    }

    function setUniswapV4TickLimits(
        bytes32 poolId,
        int24   tickLowerMin,
        int24   tickUpperMax,
        uint24  maxTickSpacing
    )
        external nonReentrant
    {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(
            ((tickLowerMin == 0) && (tickUpperMax == 0) && (maxTickSpacing == 0)) ||
            ((maxTickSpacing > 0) && (tickLowerMin < tickUpperMax)),
            "MC/invalid-ticks"
        );

        uniswapV4TickLimits[poolId] = UniswapV4Lib.TickLimits({
            tickLowerMin   : tickLowerMin,
            tickUpperMax   : tickUpperMax,
            maxTickSpacing : maxTickSpacing
        });

        emit UniswapV4TickLimitsSet(poolId, tickLowerMin, tickUpperMax, maxTickSpacing);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant {
        _checkRole(FREEZER);
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer vault functions                                                                ***/
    /**********************************************************************************************/

    function mintUSDS(uint256 usdsAmount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDS_MINT, usdsAmount);

        // Mint USDS into the buffer
        proxy.doCall(
            address(vault),
            abi.encodeCall(vault.draw, (usdsAmount))
        );

        // Transfer USDS from the buffer to the proxy
        proxy.doCall(
            address(usds),
            abi.encodeCall(usds.transferFrom, (buffer, address(proxy), usdsAmount))
        );
    }

    function burnUSDS(uint256 usdsAmount) external nonReentrant {
        _checkRole(RELAYER);
        _cancelRateLimit(LIMIT_USDS_MINT, usdsAmount);

        // Transfer USDS from the proxy to the buffer
        proxy.doCall(
            address(usds),
            abi.encodeCall(usds.transfer, (buffer, usdsAmount))
        );

        // Burn USDS from the buffer
        proxy.doCall(
            address(vault),
            abi.encodeCall(vault.wipe, (usdsAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount)
        external nonReentrant
    {
        _checkRole(RELAYER);
        _rateLimited(
            RateLimitHelpers.makeAddressAddressKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        _transfer(asset, destination, amount);
    }

    /**********************************************************************************************/
    /*** wstETH Integration                                                                     ***/
    /**********************************************************************************************/

    function depositToWstETH(uint256 amount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_WSTETH_DEPOSIT, amount);

        proxy.doCall(
            Ethereum.WETH,
            abi.encodeCall((IWETH(Ethereum.WETH)).withdraw, (amount))
        );

        proxy.doCallWithValue(
            Ethereum.WSTETH,
            "",
            amount
        );
    }

    function requestWithdrawFromWstETH(uint256 amountToRedeem)
        external nonReentrant returns (uint256[] memory)
    {
        _checkRole(RELAYER);
        _rateLimited(
            LIMIT_WSTETH_REQUEST_WITHDRAW,
            IWstETHLike(Ethereum.WSTETH).getStETHByWstETH(amountToRedeem)
        );

        proxy.doCall(
            Ethereum.WSTETH,
            abi.encodeCall(
                IERC20(Ethereum.WSTETH).approve,
                (Ethereum.WSTETH_WITHDRAW_QUEUE, amountToRedeem)
            )
        );

        uint256[] memory amountsToRedeem = new uint256[](1);
        amountsToRedeem[0] = amountToRedeem;

        ( uint256[] memory requestIds ) = abi.decode(
            proxy.doCall(
                Ethereum.WSTETH_WITHDRAW_QUEUE,
                abi.encodeCall(
                    IWithdrawalQueue(Ethereum.WSTETH_WITHDRAW_QUEUE).requestWithdrawalsWstETH,
                    (amountsToRedeem, address(proxy))
                )
            ),
            (uint256[])
        );

        return requestIds;
    }

    function claimWithdrawalFromWstETH(uint256 requestId) external nonReentrant {
        _checkRole(RELAYER);

        uint256 initialEthBalance = address(proxy).balance;

        proxy.doCall(
            Ethereum.WSTETH_WITHDRAW_QUEUE,
            abi.encodeCall(
                IWithdrawalQueue(Ethereum.WSTETH_WITHDRAW_QUEUE).claimWithdrawal,
                (requestId)
            )
        );

        uint256 ethReceived = address(proxy).balance - initialEthBalance;

        // Wrap into WETH
        proxy.doCallWithValue(
            Ethereum.WETH,
            "",
            ethReceived
        );
    }

    /**********************************************************************************************/
    /*** weETH Integration                                                                      ***/
    /**********************************************************************************************/

    function depositToWeETH(
        uint256 amount,
        uint256 minSharesOut
    )
        external nonReentrant returns (uint256 shares)
    {
        _checkRole(RELAYER);

        shares = WEETHLib.deposit({
            proxy        : proxy,
            rateLimits   : rateLimits,
            amount       : amount,
            minSharesOut : minSharesOut
        });
    }

    function requestWithdrawFromWeETH(
        address weETHModule,
        uint256 weETHShares
    )
        external nonReentrant returns (uint256 requestId)
    {
        _checkRole(RELAYER);

        requestId = WEETHLib.requestWithdraw({
            proxy       : proxy,
            rateLimits  : rateLimits,
            weETHShares : weETHShares,
            weETHModule : weETHModule
        });
    }

    function claimWithdrawalFromWeETH(
        address weETHModule,
        uint256 requestId
    )
        external nonReentrant returns (uint256 ethReceived)
    {
        _checkRole(RELAYER);

        ethReceived = WEETHLib.claimWithdrawal({
            proxy       : proxy,
            rateLimits  : rateLimits,
            requestId   : requestId,
            weETHModule : weETHModule
        });
    }

    /**********************************************************************************************/
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount, uint256 minSharesOut)
        external nonReentrant returns (uint256 shares)
    {
        _checkRole(RELAYER);

        return ERC4626Lib.deposit({
            proxy           : address(proxy),
            token           : token,
            amount          : amount,
            minSharesOut    : minSharesOut,
            maxExchangeRate : maxExchangeRates[token],
            rateLimits      : address(rateLimits),
            rateLimitId     : LIMIT_4626_DEPOSIT
        });
    }

    function withdrawERC4626(address token, uint256 amount, uint256 maxSharesIn)
        external nonReentrant returns (uint256 shares)
    {
        _checkRole(RELAYER);

        return ERC4626Lib.withdraw({
            proxy               : address(proxy),
            token               : token,
            amount              : amount,
            maxSharesIn         : maxSharesIn,
            rateLimits          : address(rateLimits),
            withdrawRateLimitId : LIMIT_4626_WITHDRAW,
            depositRateLimitId  : LIMIT_4626_DEPOSIT
        });
    }

    function redeemERC4626(address token, uint256 shares, uint256 minAssetsOut)
        external nonReentrant returns (uint256 assets)
    {
        _checkRole(RELAYER);

        return ERC4626Lib.redeem({
            proxy               : address(proxy),
            token               : token,
            shares              : shares,
            minAssetsOut        : minAssetsOut,
            rateLimits          : address(rateLimits),
            withdrawRateLimitId : LIMIT_4626_WITHDRAW,
            depositRateLimitId  : LIMIT_4626_DEPOSIT
        });
    }

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256) {
        return ERC4626Lib.EXCHANGE_RATE_PRECISION;
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external nonReentrant {
        _checkRole(RELAYER);

        AaveLib.deposit({
            proxy       : address(proxy),
            aToken      : aToken,
            amount      : amount,
            maxSlippage : maxSlippages[aToken],
            rateLimits  : address(rateLimits),
            rateLimitId : LIMIT_AAVE_DEPOSIT
        });
    }

    function withdrawAave(address aToken, uint256 amount)
        external nonReentrant returns (uint256 amountWithdrawn)
    {
        _checkRole(RELAYER);

        return AaveLib.withdraw({
            proxy               : address(proxy),
            aToken              : aToken,
            amount              : amount,
            rateLimits          : address(rateLimits),
            rateLimitWithdrawId : LIMIT_AAVE_WITHDRAW,
            rateLimitDepositId  : LIMIT_AAVE_DEPOSIT
        });
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
        external nonReentrant returns (uint256 amountOut)
    {
        _checkRole(RELAYER);

        amountOut = CurveLib.swap(CurveLib.SwapCurveParams({
            proxy        : proxy,
            rateLimits   : rateLimits,
            pool         : pool,
            rateLimitId  : LIMIT_CURVE_SWAP,
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            maxSlippage  : maxSlippages[pool]
        }));
    }

    function addLiquidityCurve(address pool, uint256[] memory depositAmounts, uint256 minLpAmount)
        external nonReentrant returns (uint256 shares)
    {
        _checkRole(RELAYER);

        shares = CurveLib.addLiquidity(CurveLib.AddLiquidityParams({
            proxy                   : proxy,
            rateLimits              : rateLimits,
            pool                    : pool,
            addLiquidityRateLimitId : LIMIT_CURVE_DEPOSIT,
            swapRateLimitId         : LIMIT_CURVE_SWAP,
            minLpAmount             : minLpAmount,
            maxSlippage             : maxSlippages[pool],
            depositAmounts          : depositAmounts
        }));
    }

    function removeLiquidityCurve(
        address          pool,
        uint256          lpBurnAmount,
        uint256[] memory minWithdrawAmounts
    )
        external nonReentrant returns (uint256[] memory withdrawnTokens)
    {
        _checkRole(RELAYER);

        withdrawnTokens = CurveLib.removeLiquidity(CurveLib.RemoveLiquidityParams({
            proxy              : proxy,
            rateLimits         : rateLimits,
            pool               : pool,
            rateLimitId        : LIMIT_CURVE_WITHDRAW,
            lpBurnAmount       : lpBurnAmount,
            minWithdrawAmounts : minWithdrawAmounts,
            maxSlippage        : maxSlippages[pool]
        }));
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
        external nonReentrant
    {
        _checkRole(RELAYER);

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
        external nonReentrant
    {
        _checkRole(RELAYER);

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
        external nonReentrant
    {
        _checkRole(RELAYER);

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
        external nonReentrant
    {
        _checkRole(RELAYER);

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

    function setDelegatedSigner(address delegatedSigner) external nonReentrant {
        _checkRole(RELAYER);

        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.setDelegatedSigner, (address(delegatedSigner)))
        );
    }

    function removeDelegatedSigner(address delegatedSigner) external nonReentrant {
        _checkRole(RELAYER);

        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.removeDelegatedSigner, (address(delegatedSigner)))
        );
    }

    // Note that Ethena's mint/redeem per-block limits include other users
    function prepareUSDeMint(uint256 usdcAmount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDE_MINT, usdcAmount);
        ApproveLib.approve(address(usdc), address(proxy), address(ethenaMinter), usdcAmount);
    }

    function prepareUSDeBurn(uint256 usdeAmount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDE_BURN, usdeAmount);
        ApproveLib.approve(address(usde), address(proxy), address(ethenaMinter), usdeAmount);
    }

    function cooldownAssetsSUSDe(uint256 usdeAmount)
        external nonReentrant returns (uint256 cooldownShares)
    {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        cooldownShares = abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function cooldownSharesSUSDe(uint256 susdeAmount)
        external nonReentrant returns (uint256 cooldownAssets)
    {
        _checkRole(RELAYER);

        cooldownAssets = abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        _rateLimited(LIMIT_SUSDE_COOLDOWN, cooldownAssets);
    }

    function unstakeSUSDe() external nonReentrant {
        _checkRole(RELAYER);

        proxy.doCall(
            address(susde),
            abi.encodeCall(susde.unstake, (address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Maple functions                                                                ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares) external nonReentrant {
        _checkRole(RELAYER);
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

    function cancelMapleRedemption(address mapleToken, uint256 shares) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAddressKey(LIMIT_MAPLE_REDEEM, mapleToken));

        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).removeShares, (shares, address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_SUPERSTATE_SUBSCRIBE, usdcAmount);

        ApproveLib.approve(address(usdc), address(proxy), address(ustb), usdcAmount);

        proxy.doCall(
            address(ustb),
            abi.encodeCall(ustb.subscribe, (usdcAmount, address(usdc)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER) {
        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        ApproveLib.approve(address(usds), address(proxy), address(daiUsds), usdsAmount);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.usdsToDai, (address(proxy), usdsAmount))
        );
    }

    function swapDAIToUSDS(uint256 daiAmount) external nonReentrant onlyRole(RELAYER) {
        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        ApproveLib.approve(address(dai), address(proxy), address(daiUsds), daiAmount);

        // Swap DAI to USDS 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.daiToUsds, (address(proxy), daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    function swapUSDSToUSDC(uint256 usdcAmount) external nonReentrant {
        _checkRole(RELAYER);

        PSMLib.swapUSDSToUSDC(PSMLib.SwapUSDSToUSDCParams({
            proxy                   : proxy,
            rateLimits              : rateLimits,
            daiUsds                 : daiUsds,
            psm                     : psm,
            usds                    : usds,
            dai                     : dai,
            rateLimitId             : LIMIT_USDS_TO_USDC,
            usdcAmount              : usdcAmount,
            psmTo18ConversionFactor : psmTo18ConversionFactor
        }));
    }

    function swapUSDCToUSDS(uint256 usdcAmount) external nonReentrant {
        _checkRole(RELAYER);

        PSMLib.swapUSDCToUSDS(PSMLib.SwapUSDCToUSDSParams({
            proxy                   : proxy,
            rateLimits              : rateLimits,
            daiUsds                 : daiUsds,
            psm                     : psm,
            dai                     : dai,
            usdc                    : usdc,
            rateLimitId             : LIMIT_USDS_TO_USDC,
            usdcAmount              : usdcAmount,
            psmTo18ConversionFactor : psmTo18ConversionFactor
        }));
    }

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    function transferTokenLayerZero(
        address oftAddress,
        uint256 amount,
        uint32  destinationEndpointId
    )
        external payable nonReentrant
    {
        _checkRole(RELAYER);

        LayerZeroLib.transferTokenLayerZero({
            proxy                 : proxy,
            rateLimits            : rateLimits,
            oftAddress            : oftAddress,
            amount                : amount,
            destinationEndpointId : destinationEndpointId,
            layerZeroRecipient    : layerZeroRecipients[destinationEndpointId]
        });
    }

    /**********************************************************************************************/
    /*** Relayer bridging functions                                                             ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain)
        external nonReentrant
    {
        _checkRole(RELAYER);

        CCTPLib.transferUSDCToCCTP(CCTPLib.TransferUSDCToCCTPParams({
            proxy             : proxy,
            rateLimits        : rateLimits,
            cctp              : cctp,
            usdc              : usdc,
            domainRateLimitId : LIMIT_USDC_TO_DOMAIN,
            cctpRateLimitId   : LIMIT_USDC_TO_CCTP,
            mintRecipient     : mintRecipients[destinationDomain],
            destinationDomain : destinationDomain,
            usdcAmount        : usdcAmount
        }));
    }

    /**********************************************************************************************/
    /*** Relayer SPK Farm functions                                                             ***/
    /**********************************************************************************************/

    function depositToFarm(address farm, uint256 usdsAmount) external nonReentrant {
        _checkRole(RELAYER);
        _rateLimited(
            keccak256(abi.encode(LIMIT_FARM_DEPOSIT, farm)),
            usdsAmount
        );

        ApproveLib.approve(address(usds), address(proxy), farm, usdsAmount);

        proxy.doCall(
            farm,
            abi.encodeCall(IFarmLike.stake, (usdsAmount))
        );
    }

    function withdrawFromFarm(address farm, uint256 usdsAmount) external nonReentrant {
        _checkRole(RELAYER);
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

    function takeFromSparkVault(address sparkVault, uint256 assetAmount) external nonReentrant {
        _checkRole(RELAYER);
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

    function otcSend(address exchange, address assetToSend, uint256 amount) external nonReentrant {
        _checkRole(RELAYER);

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

    function otcClaim(address exchange, address assetToClaim) external nonReentrant {
        _checkRole(RELAYER);

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
    ) internal {
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

    function _cancelRateLimit(bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitIncrease(key, amount);
    }

    function _rateLimitExists(bytes32 key) internal view {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "MC/invalid-action"
        );
    }

}
