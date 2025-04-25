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

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
}

interface IBuidlRedeemLike {
    function asset() external view returns(address);
    function redeem(uint256 usdcAmount) external;
}

interface ICurvePoolLike is IERC20 {
    function add_liquidity(
        uint256[] memory amounts,
        uint256 minMintAmount,
        address receiver
    ) external;
    function balances(uint256 index) external view returns (uint256);
    function coins(uint256 index) external returns (address);
    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokensOut);
    function get_virtual_price() external view returns (uint256);
    function N_COINS() external view returns (uint256);
    function remove_liquidity(
        uint256 burnAmount,
        uint256[] memory minAmounts,
        address receiver
    ) external;
    function stored_rates() external view returns (uint256[] memory);
}

interface IDaiUsdsLike {
    function dai() external view returns (address);
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
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

interface IPSMLike {
    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function fill() external returns (uint256 wad);
    function gem() external view returns (address);
    function sellGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function to18ConversionFactor() external view returns (uint256);
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

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    // NOTE: This is used to track individual transfers for offchain processing of CCTP transactions
    event CCTPTransferInitiated(
        uint64  indexed nonce,
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256 usdcAmount
    );

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
    bytes32 public constant LIMIT_BUIDL_REDEEM_CIRCLE  = keccak256("LIMIT_BUIDL_REDEEM_CIRCLE");
    bytes32 public constant LIMIT_CURVE_DEPOSIT        = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 public constant LIMIT_CURVE_SWAP           = keccak256("LIMIT_CURVE_SWAP");
    bytes32 public constant LIMIT_CURVE_WITHDRAW       = keccak256("LIMIT_CURVE_WITHDRAW");
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

    address public immutable buffer;

    IALMProxy         public immutable proxy;
    IBuidlRedeemLike  public immutable buidlRedeem;
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

    mapping(uint32 destinationDomain => bytes32 mintRecipient) public mintRecipients;

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

        buidlRedeem          = IBuidlRedeemLike(Ethereum.BUIDL_REDEEM);
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

    uint256 CENTRIFUGE_REQUEST_ID = 0;

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
    /*** Relayer BlackRock BUIDL functions                                                      ***/
    /**********************************************************************************************/

    function redeemBUIDLCircleFacility(uint256 usdcAmount) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_BUIDL_REDEEM_CIRCLE, usdcAmount);

        _approve(address(buidlRedeem.asset()), address(buidlRedeem), usdcAmount);

        proxy.doCall(
            address(buidlRedeem),
            abi.encodeCall(buidlRedeem.redeem, (usdcAmount))
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

<<<<<<< HEAD
        uint256 maxSlippage = maxSlippages[pool];

=======
        require(inputIndex != outputIndex, "MainnetController/invalid-indices");

        uint256 maxSlippage = maxSlippages[pool];
>>>>>>> dev
        require(maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(pool);

<<<<<<< HEAD
=======
        uint256 numCoins = curvePool.N_COINS();
        require(
            inputIndex < numCoins && outputIndex < numCoins,
            "MainnetController/index-too-high"
        );

>>>>>>> dev
        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Below code is simplified from the following logic.
        // `maxSlippage` was multipled first to avoid precision loss.
        //   valueIn   = amountIn * rates[inputIndex] / 1e18  // 18 decimal precision, USD
        //   tokensOut = valueIn * 1e18 / rates[outputIndex]  // Token precision, token amount
        //   result    = tokensOut * maxSlippage / 1e18
        uint256 minimumMinAmountOut = amountIn
            * rates[inputIndex]
            * maxSlippage
            / rates[outputIndex]
            / 1e18;

        require(
            minAmountOut >= minimumMinAmountOut,
            "MainnetController/min-amount-not-met"
        );

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_CURVE_SWAP, pool),
            amountIn * rates[inputIndex] / 1e18
        );

        _approve(curvePool.coins(inputIndex), pool, amountIn);

        amountOut = abi.decode(
            proxy.doCall(
                pool,
                abi.encodeCall(
                    curvePool.exchange,
                    (
<<<<<<< HEAD
                        int128(int256(inputIndex)),   // Assuming safe cast because of 8 token max
                        int128(int256(outputIndex)),  // Assuming safe cast because of 8 token max
=======
                        int128(int256(inputIndex)),   // safe cast because of 8 token max
                        int128(int256(outputIndex)),  // safe cast because of 8 token max
>>>>>>> dev
                        amountIn,
                        minAmountOut,
                        address(proxy)
                    )
                )
            ),
            (uint256)
        );
    }

    function addLiquidityCurve(
        address pool,
        uint256[] memory depositAmounts,
        uint256 minLpAmount
    )
        external returns (uint256 shares)
    {
        _checkRole(RELAYER);

        uint256 maxSlippage = maxSlippages[pool];
<<<<<<< HEAD

=======
>>>>>>> dev
        require(maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(pool);

<<<<<<< HEAD
        uint256 numCoins = curvePool.N_COINS();

        require(depositAmounts.length == numCoins, "MainnetController/invalid-deposit-amounts");
=======
        require(
            depositAmounts.length == curvePool.N_COINS(),
            "MainnetController/invalid-deposit-amounts"
        );
>>>>>>> dev

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the value of the deposited assets (e.g. USD)
        uint256 valueDeposited;
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            _approve(curvePool.coins(i), pool, depositAmounts[i]);
            valueDeposited += depositAmounts[i] * rates[i];
        }
        valueDeposited /= 1e18;

        // Ensure minimum LP amount expected is greater than max slippage amount.
        require(
            minLpAmount >= valueDeposited * maxSlippage / curvePool.get_virtual_price(),
            "MainnetController/min-amount-not-met"
        );

        // Reduce the rate limit by the aggregated underlying asset value of the deposit (e.g. USD)
        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_CURVE_DEPOSIT, pool),
            valueDeposited
        );

        shares = abi.decode(
            proxy.doCall(
                pool,
                abi.encodeCall(
                    curvePool.add_liquidity,
                    (depositAmounts, minLpAmount, address(proxy))
                )
            ),
            (uint256)
        );
<<<<<<< HEAD
=======

        // Compute the swap value by taking the difference of the current underlying
        // asset values from minted shares vs the deposited funds, converting this into an
        // aggregated swap "amount in" by dividing the total value moved by two and decrease the
        // swap rate limit by this amount.
        uint256 totalSwapped;
        for (uint256 i; i < depositAmounts.length; i++) {
            totalSwapped += _absSubtraction(
                curvePool.balances(i) * rates[i] * shares / curvePool.totalSupply(),
                depositAmounts[i] * rates[i]
            );
        }
        uint256 averageSwap = totalSwapped / 2 / 1e18;

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_CURVE_SWAP, pool),
            averageSwap
        );
>>>>>>> dev
    }

    function removeLiquidityCurve(
        address pool,
        uint256 lpBurnAmount,
        uint256[] memory minWithdrawAmounts
    )
        external returns (uint256[] memory withdrawnTokens)
    {
        _checkRole(RELAYER);

        uint256 maxSlippage = maxSlippages[pool];
<<<<<<< HEAD

=======
>>>>>>> dev
        require(maxSlippage != 0, "MainnetController/max-slippage-not-set");

        ICurvePoolLike curvePool = ICurvePoolLike(pool);

<<<<<<< HEAD
        uint256 numCoins = curvePool.N_COINS();

        require(
            minWithdrawAmounts.length == numCoins,
=======
        require(
            minWithdrawAmounts.length == curvePool.N_COINS(),
>>>>>>> dev
            "MainnetController/invalid-min-withdraw-amounts"
        );

        // Normalized to provide 36 decimal precision when multiplied by asset amount
        uint256[] memory rates = curvePool.stored_rates();

        // Aggregate the minimum values of the withdrawn assets (e.g. USD)
        uint256 valueMinWithdrawn;
<<<<<<< HEAD
        for (uint256 i = 0; i < numCoins; i++) {
=======
        for (uint256 i = 0; i < minWithdrawAmounts.length; i++) {
>>>>>>> dev
            valueMinWithdrawn += minWithdrawAmounts[i] * rates[i];
        }
        valueMinWithdrawn /= 1e18;

        // Check that the aggregated minimums are greater than the max slippage amount
        require(
            valueMinWithdrawn >= lpBurnAmount * curvePool.get_virtual_price() * maxSlippage / 1e36,
            "MainnetController/min-amount-not-met"
        );

        withdrawnTokens = abi.decode(
            proxy.doCall(
                pool,
                abi.encodeCall(
                    curvePool.remove_liquidity,
                    (lpBurnAmount, minWithdrawAmounts, address(proxy))
                )
            ),
            (uint256[])
        );

        // Aggregate value withdrawn to reduce the rate limit
        uint256 valueWithdrawn;
        for (uint256 i = 0; i < withdrawnTokens.length; i++) {
            valueWithdrawn += withdrawnTokens[i] * rates[i];
        }
        valueWithdrawn /= 1e18;

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetKey(LIMIT_CURVE_WITHDRAW, pool),
            valueWithdrawn
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
        _rateLimited(LIMIT_USDS_TO_USDC, usdcAmount);

        uint256 usdsAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        _approve(address(usds), address(daiUsds), usdsAmount);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.usdsToDai, (address(proxy), usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1
        _approve(address(dai), address(psm), usdsAmount);

        // Swap DAI to USDC through the PSM
        proxy.doCall(
            address(psm),
            abi.encodeCall(psm.buyGemNoFee, (address(proxy), usdcAmount))
        );
    }

    function swapUSDCToUSDS(uint256 usdcAmount) external {
        _checkRole(RELAYER);
        _cancelRateLimit(LIMIT_USDS_TO_USDC, usdcAmount);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC)
        _approve(address(usdc), address(psm), usdcAmount);

        // Max USDC that can be swapped to DAI in one call
        uint256 limit = dai.balanceOf(address(psm)) / psmTo18ConversionFactor;

        if (usdcAmount <= limit) {
            _swapUSDCToDAI(usdcAmount);
        } else {
            uint256 remainingUsdcToSwap = usdcAmount;

            // Refill the PSM with DAI as many times as needed to get to the full `usdcAmount`.
            // If the PSM cannot be filled with the full amount, psm.fill() will revert
            // with `DssLitePsm/nothing-to-fill` since rush() will return 0.
            // This is desired behavior because this function should only succeed if the full
            // `usdcAmount` can be swapped.
            while (remainingUsdcToSwap > 0) {
                psm.fill();

                limit = dai.balanceOf(address(psm)) / psmTo18ConversionFactor;

                uint256 swapAmount = remainingUsdcToSwap < limit ? remainingUsdcToSwap : limit;

                _swapUSDCToDAI(swapAmount);

                remainingUsdcToSwap -= swapAmount;
            }
        }

        uint256 daiAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        _approve(address(dai), address(daiUsds), daiAmount);

        // Swap DAI to USDS 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.daiToUsds, (address(proxy), daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer bridging functions                                                             ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain) external {
        _checkRole(RELAYER);
        _rateLimited(LIMIT_USDC_TO_CCTP, usdcAmount);
        _rateLimited(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            usdcAmount
        );

        bytes32 mintRecipient = mintRecipients[destinationDomain];

        require(mintRecipient != 0, "MainnetController/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC)
        _approve(address(usdc), address(cctp), usdcAmount);

        // If amount is larger than limit it must be split into multiple calls
        uint256 burnLimit = cctp.localMinter().burnLimitsPerMessage(address(usdc));

        while (usdcAmount > burnLimit) {
            _initiateCCTPTransfer(burnLimit, destinationDomain, mintRecipient);
            usdcAmount -= burnLimit;
        }

        // Send remaining amount (if any)
        if (usdcAmount > 0) {
            _initiateCCTPTransfer(usdcAmount, destinationDomain, mintRecipient);
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _approve(address token, address spender, uint256 amount) internal {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _initiateCCTPTransfer(
        uint256 usdcAmount,
        uint32  destinationDomain,
        bytes32 mintRecipient
    )
        internal
    {
        uint64 nonce = abi.decode(
            proxy.doCall(
                address(cctp),
                abi.encodeCall(
                    cctp.depositForBurn,
                    (
                        usdcAmount,
                        destinationDomain,
                        mintRecipient,
                        address(usdc)
                    )
                )
            ),
            (uint64)
        );

        emit CCTPTransferInitiated(nonce, destinationDomain, mintRecipient, usdcAmount);
    }

    function _swapUSDCToDAI(uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used)
        proxy.doCall(
            address(psm),
            abi.encodeCall(psm.sellGemNoFee, (address(proxy), usdcAmount))
        );
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

