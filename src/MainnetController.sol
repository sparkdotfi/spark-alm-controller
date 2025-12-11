// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IERC20 }   from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { IALMProxy }                                from "./interfaces/IALMProxy.sol";
import { ICCTPLike }                                from "./interfaces/CCTPInterfaces.sol";
import { IPendleMarket }                            from "./interfaces/PendleInterfaces.sol";
import { IRateLimits }                              from "./interfaces/IRateLimits.sol";
import { ISwapRouter, INonfungiblePositionManager } from "./interfaces/UniswapV3Interfaces.sol";

import "./interfaces/ILayerZero.sol";

import { CCTPLib }                        from "./libraries/CCTPLib.sol";
import { CentrifugeLib }                  from "./libraries/CentrifugeLib.sol";
import { CurveLib }                       from "./libraries/CurveLib.sol";
import { MerklLib }                       from "./libraries/MerklLib.sol";
import { IDaiUsdsLike, IPSMLike, PSMLib } from "./libraries/PSMLib.sol";
import { PendleLib }                      from "./libraries/PendleLib.sol";
import { ERC20Lib }                       from "./libraries/common/ERC20Lib.sol";
import { UniswapV3Lib }                   from "./libraries/UniswapV3Lib.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
}

interface IEthenaMinterLike {
    function setDelegatedSigner(address delegateSigner) external;
    function removeDelegatedSigner(address delegateSigner) external;
}

interface ISUSDELike is IERC4626 {
    function cooldownAssets(uint256 usdeAmount) external;
    function cooldownShares(uint256 susdeAmount) external;
    function unstake(address receiver) external;
}

interface IVaultLike {
    function buffer() external view returns (address);
    function draw(uint256 usdsAmount) external;
    function wipe(uint256 usdsAmount) external;
}

contract MainnetController is AccessControl {

    using OptionsBuilder for bytes;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CentrifugeRecipientSet(uint16 indexed centrifugeId, bytes32 recipient);
    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);
    event MaxExchangeRateSet(address indexed token, uint256 maxExchangeRate);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
    event RelayerRemoved(address indexed relayer);
    event UniswapV3PoolMaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);
    event UniswapV3PoolLowerTickUpdated(address indexed pool, int24 lowerTick);
    event UniswapV3PoolUpperTickUpdated(address indexed pool, int24 upperTick);
    event UniswapV3PoolTwapSecondsAgoUpdated(address indexed pool, uint32 twapSecondsAgo);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    uint256 public constant EXCHANGE_RATE_PRECISION = 1e36;

    bytes32 public FREEZER = keccak256("FREEZER");
    bytes32 public RELAYER = keccak256("RELAYER");

    bytes32 public LIMIT_4626_DEPOSIT         = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public LIMIT_4626_WITHDRAW        = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public LIMIT_7540_DEPOSIT         = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public LIMIT_7540_REDEEM          = keccak256("LIMIT_7540_REDEEM");
    bytes32 public LIMIT_AAVE_DEPOSIT         = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public LIMIT_AAVE_WITHDRAW        = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public LIMIT_ASSET_TRANSFER       = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public LIMIT_CENTRIFUGE_TRANSFER  = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
    bytes32 public LIMIT_CURVE_DEPOSIT        = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public LIMIT_CURVE_SWAP           = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public LIMIT_CURVE_WITHDRAW       = keccak256("LIMIT_CURVE_WITHDRAW");
    bytes32 public LIMIT_LAYERZERO_TRANSFER   = keccak256("LIMIT_LAYERZERO_TRANSFER");
    bytes32 public LIMIT_PENDLE_PT_REDEEM     = keccak256("LIMIT_PENDLE_PT_REDEEM");
    bytes32 public LIMIT_SUSDE_COOLDOWN       = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 public LIMIT_USDC_TO_CCTP         = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public LIMIT_USDC_TO_DOMAIN       = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 public LIMIT_USDE_BURN            = keccak256("LIMIT_USDE_BURN");
    bytes32 public LIMIT_USDE_MINT            = keccak256("LIMIT_USDE_MINT");
    bytes32 public LIMIT_USDS_MINT            = keccak256("LIMIT_USDS_MINT");
    bytes32 public LIMIT_USDS_TO_USDC         = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 public LIMIT_UNISWAP_V3_DEPOSIT   = keccak256("LIMIT_UNISWAP_V3_DEPOSIT");
    bytes32 public LIMIT_UNISWAP_V3_SWAP      = keccak256("LIMIT_UNISWAP_V3_SWAP");
    bytes32 public LIMIT_UNISWAP_V3_WITHDRAW  = keccak256("LIMIT_UNISWAP_V3_WITHDRAW");

    uint256 internal CENTRIFUGE_REQUEST_ID = 0;

    // @dev https://github.com/uniswap/v4-core/blob/80311e34080fee64b6fc6c916e9a51a437d0e482/src/libraries/TickMath.sol#L20-L23
    int24 internal constant MIN_TICK = -887_272;
    int24 internal constant MAX_TICK =  887_272;

    address public buffer;

    IALMProxy                   public proxy;
    ICCTPLike                   public cctp;
    IDaiUsdsLike                public daiUsds;
    IEthenaMinterLike           public ethenaMinter;
    IPSMLike                    public psm;
    IRateLimits                 public rateLimits;
    IVaultLike                  public vault;
    ISwapRouter                 public uniswapV3Router;
    INonfungiblePositionManager public uniswapV3PositionManager;

    IERC20     public dai;
    IERC20     public usds;
    IERC20     public usde;
    IERC20     public usdc;
    ISUSDELike public susde;

    uint256 public psmTo18ConversionFactor;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(address pool => UniswapV3Lib.UniswapV3PoolParams params) public uniswapV3PoolParams;

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;
    mapping(uint16 centrifugeId          => bytes32 recipient)          public centrifugeRecipients;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

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
        address cctp_,
        address uniswapV3Router_,
        address uniswapV3PositionManager_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy                    = IALMProxy(proxy_);
        rateLimits               = IRateLimits(rateLimits_);
        vault                    = IVaultLike(vault_);
        buffer                   = IVaultLike(vault_).buffer();
        psm                      = IPSMLike(psm_);
        daiUsds                  = IDaiUsdsLike(daiUsds_);
        cctp                     = ICCTPLike(cctp_);
        uniswapV3Router          = ISwapRouter(uniswapV3Router_);
        uniswapV3PositionManager = INonfungiblePositionManager(uniswapV3PositionManager_);

        ethenaMinter = IEthenaMinterLike(Ethereum.ETHENA_MINTER);

        susde = ISUSDELike(Ethereum.SUSDE);
        dai   = IERC20(daiUsds.dai());
        usdc  = IERC20(psm.gem());
        usds  = IERC20(Ethereum.USDS);
        usde  = IERC20(Ethereum.USDE);

        psmTo18ConversionFactor = psm.to18ConversionFactor();
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMintRecipient(uint32 destinationDomain, bytes32 mintRecipient) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        mintRecipients[destinationDomain] = mintRecipient;
        emit MintRecipientSet(destinationDomain, mintRecipient);
    }

    function setLayerZeroRecipient(
        uint32  destinationEndpointId,
        bytes32 layerZeroRecipient
    )
        external
    {
        _checkRole(DEFAULT_ADMIN_ROLE);
        layerZeroRecipients[destinationEndpointId] = layerZeroRecipient;
        emit LayerZeroRecipientSet(destinationEndpointId, layerZeroRecipient);
    }

    function setMaxSlippage(address pool, uint256 maxSlippage) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        require(maxSlippage <= 1e18, "MainnetController/max-slippage-out-of-bounds");
        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta) external {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(
            maxTickDelta > 0 &&
            maxTickDelta <= UniswapV3Lib.MAX_TICK_DELTA,
            "MainnetController/max-tick-delta-out-of-bounds"
        );

        UniswapV3Lib.UniswapV3PoolParams storage params = uniswapV3PoolParams[pool];
        params.swapMaxTickDelta = maxTickDelta;
        emit UniswapV3PoolMaxTickDeltaSet(pool, maxTickDelta);
    }

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UniswapV3Lib.UniswapV3PoolParams storage params = uniswapV3PoolParams[pool];
        require(lowerTickBound >= MIN_TICK && lowerTickBound < params.addLiquidityTickBounds.upper, "MainnetController/lower-tick-out-of-bounds");

        params.addLiquidityTickBounds.lower = lowerTickBound;
        emit UniswapV3PoolLowerTickUpdated(pool, lowerTickBound);
    }

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UniswapV3Lib.UniswapV3PoolParams storage params = uniswapV3PoolParams[pool];
        require(upperTickBound > params.addLiquidityTickBounds.lower && upperTickBound <= MAX_TICK, "MainnetController/upper-tick-out-of-bounds");

        params.addLiquidityTickBounds.upper = upperTickBound;
        emit UniswapV3PoolUpperTickUpdated(pool, upperTickBound);
    }

    function setUniswapV3TwapSecondsAgo(address pool, uint32 twapSecondsAgo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UniswapV3Lib.UniswapV3PoolParams storage params = uniswapV3PoolParams[pool];
        // Required due to casting in UniswapV3OracleLibrary.consult
        // Limits twapSecondsAgo to approximately 68 years
        require(twapSecondsAgo < uint32(type(int32).max), "MainnetController/twap-seconds-ago-out-of-bounds");
        params.twapSecondsAgo = twapSecondsAgo;
        emit UniswapV3PoolTwapSecondsAgoUpdated(pool, twapSecondsAgo);
    }

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        centrifugeRecipients[centrifugeId] = recipient;
        emit CentrifugeRecipientSet(centrifugeId, recipient);
    }

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external {
        _checkRole(DEFAULT_ADMIN_ROLE);

        require(token != address(0), "MainnetController/token-zero-address");

        emit MaxExchangeRateSet(
            token,
            maxExchangeRates[token] = _getExchangeRate(shares, maxExpectedAssets)
        );
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external {
        _checkRole(FREEZER);
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer vault functions                                                                ***/
    /**********************************************************************************************/

    function mintUSDS(uint256 usdsAmount) external {
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

    function burnUSDS(uint256 usdsAmount) external {
        _checkRole(RELAYER);
        _cancelRateLimit(LIMIT_USDS_MINT, usdsAmount);

        // Transfer USDS from the proxy to the buffer
        ERC20Lib.transfer(proxy, address(usds), buffer, usdsAmount);

        // Burn USDS from the buffer
        proxy.doCall(
            address(vault),
            abi.encodeCall(vault.wipe, (usdsAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount) external {
        _checkRole(RELAYER);
        _rateLimited(
            RateLimitHelpers.makeAssetDestinationKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        ERC20Lib.transfer(proxy, asset, destination, amount);
    }

    /**********************************************************************************************/
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount) external returns (uint256 shares) {
        _checkRole(RELAYER);
        _rateLimitedAsset(LIMIT_4626_DEPOSIT, token, amount);

        // Note that whitelist is done by rate limits
        IERC20 asset = IERC20(IERC4626(token).asset());

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        ERC20Lib.approve(proxy, address(asset), token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares
        shares = abi.decode(
            proxy.doCall(
                token,
                abi.encodeCall(IERC4626(token).deposit, (amount, address(proxy)))
            ),
            (uint256)
        );

        require(
            _getExchangeRate(shares, amount) <= maxExchangeRates[token],
            "MainnetController/exchange-rate-too-high"
        );
    }

    function withdrawERC4626(address token, uint256 amount) external returns (uint256 shares) {
        _checkRole(RELAYER);
        _rateLimitedAsset(LIMIT_4626_WITHDRAW, token, amount);

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        shares = abi.decode(
            proxy.doCall(
                token,
                abi.encodeCall(IERC4626(token).withdraw, (amount, address(proxy), address(proxy)))
            ),
            (uint256)
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function redeemERC4626(address token, uint256 shares) external returns (uint256 assets) {
        _checkRole(RELAYER);

        // Redeem shares for assets from the token, decode the resulting assets.
        // Assumes proxy has adequate token shares.
        assets = abi.decode(
            proxy.doCall(
                token,
                abi.encodeCall(IERC4626(token).redeem, (shares, address(proxy), address(proxy)))
            ),
            (uint256)
        );

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_4626_WITHDRAW, token),
            assets
        );
    }

    /**********************************************************************************************/
    /*** Relayer ERC7540 functions                                                              ***/
    /**********************************************************************************************/

    function requestDepositERC7540(address token, uint256 amount) external {
        _checkRole(RELAYER);
        _rateLimitedAsset(LIMIT_7540_DEPOSIT, token, amount);

        // Note that whitelist is done by rate limits
        IERC20 asset = IERC20(IERC7540(token).asset());

        // Approve asset to vault from the proxy (assumes the proxy has enough of the asset).
        ERC20Lib.approve(proxy, address(asset), token, amount);

        // Submit deposit request by transferring assets
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).requestDeposit, (amount, address(proxy), address(proxy)))
        );
    }

    function claimDepositERC7540(address token) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token));

        uint256 shares = IERC7540(token).maxMint(address(proxy));

        // Claim shares from the vault to the proxy
        proxy.doCall(
            token,
            abi.encodeCall(IERC4626(token).mint, (shares, address(proxy)))
        );
    }

    function requestRedeemERC7540(address token, uint256 shares) external {
        _checkRole(RELAYER);
        _rateLimitedAsset(
            LIMIT_7540_REDEEM,
            token,
            IERC7540(token).convertToAssets(shares)
        );

        // Submit redeem request by transferring shares
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).requestRedeem, (shares, address(proxy), address(proxy)))
        );
    }

    function claimRedeemERC7540(address token) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token));

        uint256 assets = IERC7540(token).maxWithdraw(address(proxy));

        // Claim assets from the vault to the proxy
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).withdraw, (assets, address(proxy), address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Centrifuge functions                                                           ***/
    /**********************************************************************************************/

    // NOTE: These cancelation methods are compatible with ERC-7887

    function cancelCentrifugeDepositRequest(address token) external {
        _checkRole(RELAYER);
        CentrifugeLib.cancelCentrifugeDepositRequest(centrifugeDepositRequestParams(token));
    }

    function claimCentrifugeCancelDepositRequest(address token) external {
        _checkRole(RELAYER);
        CentrifugeLib.claimCentrifugeCancelDepositRequest(centrifugeDepositRequestParams(token));
    }

    function cancelCentrifugeRedeemRequest(address token) external {
        _checkRole(RELAYER);
        CentrifugeLib.cancelCentrifugeRedeemRequest(centrifugeRedeemRequestParams(token));
    }

    function claimCentrifugeCancelRedeemRequest(address token) external {
        _checkRole(RELAYER);
        CentrifugeLib.claimCentrifugeCancelRedeemRequest(centrifugeRedeemRequestParams(token));
    }

    function transferSharesCentrifuge(
        address token,
        uint128 amount,
        uint16  destinationCentrifugeId
    )
        external payable
    {
        _checkRole(RELAYER);
        CentrifugeLib.transferSharesCentrifuge(
            CentrifugeLib.CentrifugeTransferParams({
                proxy                   : proxy,
                rateLimits              : rateLimits,
                token                   : token,
                amount                  : amount,
                recipient               : centrifugeRecipients[destinationCentrifugeId],
                destinationCentrifugeId : destinationCentrifugeId,
                rateLimitId             : LIMIT_CENTRIFUGE_TRANSFER
            })
        );
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external {
        _checkRole(RELAYER);
        _rateLimitedAsset(LIMIT_AAVE_DEPOSIT, aToken, amount);

        require(maxSlippages[aToken] != 0, "MainnetController/max-slippage-not-set");

        IERC20    underlying = IERC20(IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS());
        IAavePool pool       = IAavePool(IATokenWithPool(aToken).POOL());

        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(proxy));

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        ERC20Lib.approve(proxy, address(underlying), address(pool), amount);

        // Deposit underlying into Aave pool, proxy receives aTokens
        proxy.doCall(
            address(pool),
            abi.encodeCall(pool.supply, (address(underlying), amount, address(proxy), 0))
        );

        uint256 newATokens = IERC20(aToken).balanceOf(address(proxy)) - aTokenBalance;

        require(
            newATokens >= amount * maxSlippages[aToken] / 1e18,
            "MainnetController/slippage-too-high"
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function withdrawAave(address aToken, uint256 amount)
        external
        returns (uint256 amountWithdrawn)
    {
        _checkRole(RELAYER);

        IAavePool pool = IAavePool(IATokenWithPool(aToken).POOL());

        // Withdraw underlying from Aave pool, decode resulting amount withdrawn.
        // Assumes proxy has adequate aTokens.
        amountWithdrawn = abi.decode(
            proxy.doCall(
                address(pool),
                abi.encodeCall(
                    pool.withdraw,
                    (IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS(), amount, address(proxy))
                )
            ),
            (uint256)
        );

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_AAVE_WITHDRAW, aToken),
            amountWithdrawn
        );
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
        external returns (uint256 amountOut)
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

    function addLiquidityCurve(
        address pool,
        uint256[] memory depositAmounts,
        uint256 minLpAmount
    )
        external returns (uint256 shares)
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
        address   pool,
        uint256   lpBurnAmount,
        uint256[] memory minWithdrawAmounts
    )
        external returns (uint256[] memory withdrawnTokens)
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
    /*** Relayer UniswapV3 functions                                                            ***/
    /**********************************************************************************************/
    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  swapMaxTickDelta
    )
        external returns (uint256 amountOut)
    {
        _checkRole(RELAYER);

        amountOut = UniswapV3Lib.swap(
            UniswapV3Lib.UniV3Context({
                proxy       : proxy,
                rateLimits  : rateLimits,
                rateLimitId : LIMIT_UNISWAP_V3_SWAP,
                pool        : pool
            }),
            UniswapV3Lib.SwapParams({
                router       : uniswapV3Router,
                tokenIn      : tokenIn,
                amountIn     : amountIn,
                minAmountOut : minAmountOut,
                maxSlippage  : maxSlippages[pool],
                tickDelta    : swapMaxTickDelta,
                poolParams   : uniswapV3PoolParams[pool]
            })
        );
    }

    function addLiquidityUniswapV3(
        address                   pool,
        uint256                   tokenId,
        UniswapV3Lib.Tick         calldata tick,
        UniswapV3Lib.TokenAmounts calldata target,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                   deadline
    )
        external
        returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_)
    {
        _checkRole(RELAYER);

        UniswapV3Lib.UniswapV3PoolParams memory poolParams = uniswapV3PoolParams[pool];
        uint256 maxSlippage                                = maxSlippages[pool];

        (tokenId_, liquidity_, amount0_, amount1_) = UniswapV3Lib.addLiquidity(
            UniswapV3Lib.UniV3Context({
                proxy       : proxy,
                rateLimits  : rateLimits,
                rateLimitId : LIMIT_UNISWAP_V3_DEPOSIT,
                pool        : pool
            }),
            UniswapV3Lib.AddLiquidityParams({
                positionManager : uniswapV3PositionManager,
                tokenId         : tokenId,
                tick            : tick,
                target          : target,
                min             : min,
                tickBounds      : poolParams.addLiquidityTickBounds,
                maxSlippage     : maxSlippage,
                deadline        : deadline,
                twapSecondsAgo  : poolParams.twapSecondsAgo
            })
        );
    }

    function removeLiquidityUniswapV3(
        address                   pool,
        uint256                   tokenId,
        uint128                   liquidity,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                   deadline
    )
        external
        onlyRole(RELAYER)
        returns (uint256 amount0Collected, uint256 amount1Collected)
    {
        return UniswapV3Lib.removeLiquidity(
            UniswapV3Lib.UniV3Context({
                proxy       : proxy,
                rateLimits  : rateLimits,
                rateLimitId : LIMIT_UNISWAP_V3_WITHDRAW,
                pool        : pool
            }),
            UniswapV3Lib.RemoveLiquidityParams({
                positionManager : uniswapV3PositionManager,
                tokenId         : tokenId,
                liquidity       : liquidity,
                min             : min,
                maxSlippage     : maxSlippages[pool],
                deadline        : deadline
            })
        );
    }


    /**********************************************************************************************/
    /*** Relayer Ethena functions                                                               ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner) external {
        _checkRole(RELAYER);

        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.setDelegatedSigner, (address(delegatedSigner)))
        );
    }

    function removeDelegatedSigner(address delegatedSigner) external {
        _checkRole(RELAYER);

        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.removeDelegatedSigner, (address(delegatedSigner)))
        );
    }

    // Note that Ethena's mint/redeem per-block limits include other users
    function prepareUSDeMint(uint256 usdcAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDE_MINT, usdcAmount);
        ERC20Lib.approve(proxy, address(usdc), address(ethenaMinter), usdcAmount);
    }

    function prepareUSDeBurn(uint256 usdeAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDE_BURN, usdeAmount);
        ERC20Lib.approve(proxy, address(usde), address(ethenaMinter), usdeAmount);
    }

    function cooldownAssetsSUSDe(uint256 usdeAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        proxy.doCall(
            address(susde),
            abi.encodeCall(susde.cooldownAssets, (usdeAmount))
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function cooldownSharesSUSDe(uint256 susdeAmount)
        external
        returns (uint256 cooldownAmount)
    {
        _checkRole(RELAYER);

        cooldownAmount = abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        rateLimits.triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, cooldownAmount);
    }

    function unstakeSUSDe() external {
        _checkRole(RELAYER);

        proxy.doCall(
            address(susde),
            abi.encodeCall(susde.unstake, (address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Pendle functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: DO NOT use for markets with non-standard SYs, without additional testing
    //       targeting each onboarded non-standard SY market.
    //       (Non-standard SYs: ePENDLE, mPENDLE, aTokens (aUSDC, aUSDT))
    function redeemPendlePT(
        address pendleMarket,
        uint256 pyAmountIn,
        uint256 minAmountOut
    ) external {
        _checkRole(RELAYER);

        PendleLib.redeemPendlePT(PendleLib.RedeemPendlePTParams({
            proxy        : proxy,
            rateLimits   : rateLimits,
            rateLimitId  : LIMIT_PENDLE_PT_REDEEM,
            pendleMarket : IPendleMarket(pendleMarket),
            pendleRouter : Ethereum.PENDLE_ROUTER,
            pyAmountIn   : pyAmountIn,
            minAmountOut : minAmountOut
        }));
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount)
        external
        onlyRole(RELAYER)
    {
        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        ERC20Lib.approve(proxy, address(usds), address(daiUsds), usdsAmount);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.usdsToDai, (address(proxy), usdsAmount))
        );
    }

    function swapDAIToUSDS(uint256 daiAmount)
        external
        onlyRole(RELAYER)
    {
        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        ERC20Lib.approve(proxy, address(dai), address(daiUsds), daiAmount);

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
    function swapUSDSToUSDC(uint256 usdcAmount) external {
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

    function swapUSDCToUSDS(uint256 usdcAmount) external {
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
        external payable
    {
        _checkRole(RELAYER);
        _rateLimited(
            keccak256(abi.encode(LIMIT_LAYERZERO_TRANSFER, oftAddress, destinationEndpointId)),
            amount
        );

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZero(oftAddress).approvalRequired()) {
            ERC20Lib.approve(proxy, ILayerZero(oftAddress).token(), oftAddress, amount);
        }

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : layerZeroRecipients[destinationEndpointId],
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( ,, OFTReceipt memory receipt ) = ILayerZero(oftAddress).quoteOFT(sendParams);
        sendParams.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = ILayerZero(oftAddress).quoteSend(sendParams, false);

        proxy.doCallWithValue{value: fee.nativeFee}(
            oftAddress,
            abi.encodeCall(ILayerZero.send, (sendParams, fee, address(proxy))),
            fee.nativeFee
        );
    }

    /**********************************************************************************************/
    /*** Relayer Merkl functions                                                                ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address operator) external {
        _checkRole(RELAYER);

        MerklLib.toggleOperator(MerklLib.MerklToggleOperatorParams({
            proxy       : proxy,
            distributor : Ethereum.MERKL_DISTRIBUTOR,
            operator    : operator
        }));
    }

    /**********************************************************************************************/
    /*** Relayer bridging functions                                                             ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain) external {
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
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

    function _rateLimitedAsset(bytes32 key, address asset, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(RateLimitHelpers.makeAssetKey(key, asset), amount);
    }

    function _cancelRateLimit(bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitIncrease(key, amount);
    }

    function _rateLimitExists(bytes32 key) internal view {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "MainnetController/invalid-action"
        );
    }

    /**********************************************************************************************/
    /*** Centrifuge Library helper functions                                                    ***/
    /**********************************************************************************************/

    function centrifugeDepositRequestParams(
        address token
    ) internal view returns(CentrifugeLib.CentrifugeRequestParams memory) {
        return CentrifugeLib.CentrifugeRequestParams({
            proxy       : proxy,
            rateLimits  : rateLimits,
            token       : token,
            rateLimitId : LIMIT_7540_DEPOSIT,
            requestId   : CENTRIFUGE_REQUEST_ID
        });
    }

    function centrifugeRedeemRequestParams(
        address token
    ) internal view returns(CentrifugeLib.CentrifugeRequestParams memory) {
        return CentrifugeLib.CentrifugeRequestParams({
            proxy       : proxy,
            rateLimits  : rateLimits,
            token       : token,
            rateLimitId : LIMIT_7540_REDEEM,
            requestId   : CENTRIFUGE_REQUEST_ID
        });
    }

    /**********************************************************************************************/
    /*** Exchange rate helper functions                                                         ***/
    /**********************************************************************************************/

    function _getExchangeRate(uint256 shares, uint256 assets) internal pure returns (uint256) {
        // Return 0 for zero assets first, to handle the valid case of 0 shares and 0 assets.
        if (assets == 0) return 0;

        // Zero shares with non-zero assets is invalid (infinite exchange rate).
        if (shares == 0) revert("MainnetController/zero-shares");

        return (EXCHANGE_RATE_PRECISION * assets) / shares;
    }

}
