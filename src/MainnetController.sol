// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

import { IMetaMorpho, Id, MarketAllocation } from "metamorpho/interfaces/IMetaMorpho.sol";

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { ICCTPLike }   from "./interfaces/CCTPInterfaces.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import  "./interfaces/ILayerZero.sol";

import { CCTPLib }                        from "./libraries/CCTPLib.sol";
import { CurveLib }                       from "./libraries/CurveLib.sol";
import { IDaiUsdsLike, IPSMLike, PSMLib } from "./libraries/PSMLib.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
}

interface IEthenaMinterLike {
    function setDelegatedSigner(address delegateSigner) external;
    function removeDelegatedSigner(address delegateSigner) external;
}

interface ICentrifugeToken is IERC7540 {
    function cancelDepositRequest(uint256 requestId, address controller) external;
    function cancelRedeemRequest(uint256 requestId, address controller) external;
    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external returns (uint256 assets);
    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external returns (uint256 shares);
}

interface IMapleTokenLike is IERC4626 {
    function requestRedeem(uint256 shares, address receiver) external;
    function removeShares(uint256 shares, address receiver) external;
}

interface ISSRedemptionLike is IERC20 {
    function calculateUsdcOut(uint256 ustbAmount)
        external view returns (uint256 usdcOutAmount, uint256 usdPerUstbChainlinkRaw);
    function redeem(uint256 ustbAmout) external;
}

interface ISUSDELike is IERC4626 {
    function cooldownAssets(uint256 usdeAmount) external;
    function cooldownShares(uint256 susdeAmount) external;
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

contract MainnetController is AccessControl {

    using OptionsBuilder for bytes;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_4626_DEPOSIT         = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant LIMIT_4626_WITHDRAW        = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public constant LIMIT_7540_DEPOSIT         = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant LIMIT_7540_REDEEM          = keccak256("LIMIT_7540_REDEEM");
    bytes32 public constant LIMIT_AAVE_DEPOSIT         = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant LIMIT_AAVE_WITHDRAW        = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public constant LIMIT_ASSET_TRANSFER       = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public constant LIMIT_CURVE_DEPOSIT        = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant LIMIT_CURVE_SWAP           = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant LIMIT_CURVE_WITHDRAW       = keccak256("LIMIT_CURVE_WITHDRAW");
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER   = keccak256("LIMIT_LAYERZERO_TRANSFER");
    bytes32 public constant LIMIT_MAPLE_REDEEM         = keccak256("LIMIT_MAPLE_REDEEM");
    bytes32 public constant LIMIT_SUPERSTATE_REDEEM    = keccak256("LIMIT_SUPERSTATE_REDEEM");
    bytes32 public constant LIMIT_SUPERSTATE_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");
    bytes32 public constant LIMIT_SUSDE_COOLDOWN       = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 public constant LIMIT_USDC_TO_CCTP         = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_USDC_TO_DOMAIN       = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 public constant LIMIT_USDE_BURN            = keccak256("LIMIT_USDE_BURN");
    bytes32 public constant LIMIT_USDE_MINT            = keccak256("LIMIT_USDE_MINT");
    bytes32 public constant LIMIT_USDS_MINT            = keccak256("LIMIT_USDS_MINT");
    bytes32 public constant LIMIT_USDS_TO_USDC         = keccak256("LIMIT_USDS_TO_USDC");

    uint256 internal constant CENTRIFUGE_REQUEST_ID = 0;

    address public immutable buffer;

    IALMProxy         public immutable proxy;
    ICCTPLike         public immutable cctp;
    IDaiUsdsLike      public immutable daiUsds;
    IEthenaMinterLike public immutable ethenaMinter;
    IPSMLike          public immutable psm;
    IRateLimits       public immutable rateLimits;
    ISSRedemptionLike public immutable superstateRedemption;
    IVaultLike        public immutable vault;

    IERC20     public immutable dai;
    IERC20     public immutable usds;
    IERC20     public immutable usde;
    IERC20     public immutable usdc;
    IUSTBLike  public immutable ustb;
    ISUSDELike public immutable susde;

    uint256 public immutable psmTo18ConversionFactor;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;

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

        ethenaMinter         = IEthenaMinterLike(Ethereum.ETHENA_MINTER);
        superstateRedemption = ISSRedemptionLike(Ethereum.SUPERSTATE_REDEMPTION);

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
        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
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

    function transferAsset(address asset, address destination, uint256 amount) external {
        _checkRole(RELAYER);
        _rateLimited(
            RateLimitHelpers.makeAssetDestinationKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transfer, (destination, amount))
        );
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
        _approve(address(asset), token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares
        shares = abi.decode(
            proxy.doCall(
                token,
                abi.encodeCall(IERC4626(token).deposit, (amount, address(proxy)))
            ),
            (uint256)
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
        _approve(address(asset), token, amount);

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
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token));

        // NOTE: While the cancelation is pending, no new deposit request can be submitted
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeToken(token).cancelDepositRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy))
            )
        );
    }

    function claimCentrifugeCancelDepositRequest(address token) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token));

        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeToken(token).claimCancelDepositRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy), address(proxy))
            )
        );
    }

    function cancelCentrifugeRedeemRequest(address token) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token));

        // NOTE: While the cancelation is pending, no new redeem request can be submitted
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeToken(token).cancelRedeemRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy))
            )
        );
    }

    function claimCentrifugeCancelRedeemRequest(address token) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token));

        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeToken(token).claimCancelRedeemRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy), address(proxy))
            )
        );
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount) external {
        _checkRole(RELAYER);
        _rateLimitedAsset(LIMIT_AAVE_DEPOSIT, aToken, amount);

        IERC20    underlying = IERC20(IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS());
        IAavePool pool       = IAavePool(IATokenWithPool(aToken).POOL());

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        _approve(address(underlying), address(pool), amount);

        // Deposit underlying into Aave pool, proxy receives aTokens
        proxy.doCall(
            address(pool),
            abi.encodeCall(pool.supply, (address(underlying), amount, address(proxy), 0))
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
        address pool,
        uint256 lpBurnAmount,
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
        _approve(address(usdc), address(ethenaMinter), usdcAmount);
    }

    function prepareUSDeBurn(uint256 usdeAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDE_BURN, usdeAmount);
        _approve(address(usde), address(ethenaMinter), usdeAmount);
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
    /*** Relayer Maple functions                                                                ***/
    /**********************************************************************************************/

    function requestMapleRedemption(address mapleToken, uint256 shares) external {
        _checkRole(RELAYER);
        _rateLimitedAsset(
            LIMIT_MAPLE_REDEEM,
            mapleToken,
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        );

        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).requestRedeem, (shares, address(proxy)))
        );
    }

    function cancelMapleRedemption(address mapleToken, uint256 shares) external {
        _checkRole(RELAYER);
        _rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_MAPLE_REDEEM, mapleToken));

        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).removeShares, (shares, address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_SUPERSTATE_SUBSCRIBE, usdcAmount);

        _approve(address(usdc), address(ustb), usdcAmount);

        proxy.doCall(
            address(ustb),
            abi.encodeCall(ustb.subscribe, (usdcAmount, address(usdc)))
        );
    }

    // NOTE: Rate limited outside of modifier because of tuple return
    function redeemSuperstate(uint256 ustbAmount) external {
        _checkRole(RELAYER);

        ( uint256 usdcAmount, ) = superstateRedemption.calculateUsdcOut(ustbAmount);

        rateLimits.triggerRateLimitDecrease(LIMIT_SUPERSTATE_REDEEM, usdcAmount);

        _approve(address(ustb), address(superstateRedemption), ustbAmount);

        proxy.doCall(
            address(superstateRedemption),
            abi.encodeCall(superstateRedemption.redeem, (ustbAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer DaiUsds functions                                                              ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount)
        external
        onlyRole(RELAYER)
    {
        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        _approve(address(usds), address(daiUsds), usdsAmount);

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
        _approve(address(dai), address(daiUsds), daiAmount);

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
        external
    {
        _checkRole(RELAYER);
        _rateLimited(
            keccak256(abi.encode(LIMIT_LAYERZERO_TRANSFER, oftAddress, destinationEndpointId)),
            amount
        );

        _approve(ILayerZero(oftAddress).token(), oftAddress, amount);

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

        proxy.doCallWithValue(
            oftAddress,
            abi.encodeCall(ILayerZero.send, (sendParams, fee, address(proxy))),
            fee.nativeFee
        );
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
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: This logic was inspired by OpenZeppelin's forceApprove in SafeERC20 library
    function _approve(address token, address spender, uint256 amount) internal {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token
        ( bool success, bytes memory data )
            = address(proxy).call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        // Decode the first 32 bytes of the data, ALMProxy returns 96 bytes
        bytes32 result;
        assembly { result := mload(add(data, 32)) }

        // Decode the result to check if the approval was successful
        bool decodedSuccess = (data.length == 0) || result != bytes32(0);

        // If call succeeded with expected calldata, return
        if (success && decodedSuccess) return;

        // If call reverted, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
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

}

