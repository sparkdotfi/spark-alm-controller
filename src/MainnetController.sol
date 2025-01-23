// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

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

interface IDaiUsdsLike {
    function dai() external view returns(address);
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
}

interface IERC7540 is IERC4626 {
    function requestDeposit(uint256 assets, address controller, address owner)
        external returns (uint256);
    function requestRedeem(uint256 shares, address controller, address owner)
        external returns (uint256);
}

interface IEthenaMinterLike {
    function setDelegatedSigner(address delegateSigner) external;
    function removeDelegatedSigner(address delegateSigner) external;
}

interface IMapleTokenLike is IERC4626 {
    function requestRedeem(uint256 shares, address receiver) external;
    function removeShares(uint256 shares, address receiver) external;
}

interface IPSMLike {
    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function fill() external returns (uint256 wad);
    function gem() external view returns(address);
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
    function buffer() external view returns(address);
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

    event Frozen();

    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);

    event Reactivated();

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

    bool public active;

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

        active = true;
    }

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier isActive {
        require(active, "MainnetController/not-active");
        _;
    }

    modifier rateLimited(bytes32 key, uint256 amount) {
        rateLimits.triggerRateLimitDecrease(key, amount);
        _;
    }

    modifier cancelRateLimit(bytes32 key, uint256 amount) {
        rateLimits.triggerRateLimitIncrease(key, amount);
        _;
    }

    modifier rateLimitExists(bytes32 key) {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "MainnetController/invalid-action"
        );
        _;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMintRecipient(uint32 destinationDomain, bytes32 mintRecipient)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        mintRecipients[destinationDomain] = mintRecipient;
        emit MintRecipientSet(destinationDomain, mintRecipient);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function freeze() external onlyRole(FREEZER) {
        active = false;
        emit Frozen();
    }

    function reactivate() external onlyRole(DEFAULT_ADMIN_ROLE) {
        active = true;
        emit Reactivated();
    }

    /**********************************************************************************************/
    /*** Relayer vault functions                                                                ***/
    /**********************************************************************************************/

    function mintUSDS(uint256 usdsAmount)
        external onlyRole(RELAYER) isActive rateLimited(LIMIT_USDS_MINT, usdsAmount)
    {
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

    function burnUSDS(uint256 usdsAmount)
        external onlyRole(RELAYER) isActive cancelRateLimit(LIMIT_USDS_MINT, usdsAmount)
    {
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
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetDestinationKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        )
    {
        proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transfer, (destination, amount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_4626_DEPOSIT, token),
            amount
        )
        returns (uint256 shares)
    {
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

    function withdrawERC4626(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_4626_WITHDRAW, token),
            amount
        )
        returns (uint256 shares)
    {
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
    function redeemERC4626(address token, uint256 shares)
        external onlyRole(RELAYER) isActive returns (uint256 assets)
    {
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

    function requestDepositERC7540(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token),
            amount
        )
    {
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

    function claimDepositERC7540(address token)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token))
    {
        uint256 shares = IERC7540(token).maxMint(address(proxy));

        // Claim shares from the vault to the proxy
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).mint, (shares, address(proxy)))
        );
    }

    function requestRedeemERC7540(address token, uint256 shares)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token),
            IERC7540(token).convertToAssets(shares)
        )
    {
        // Submit redeem request by transferring shares
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).requestRedeem, (shares, address(proxy), address(proxy)))
        );
    }

    function claimRedeemERC7540(address token)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token))
    {
        uint256 assets = IERC7540(token).maxWithdraw(address(proxy));

        // Claim assets from the vault to the proxy
        proxy.doCall(
            token,
            abi.encodeCall(IERC7540(token).withdraw, (assets, address(proxy), address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_AAVE_DEPOSIT, aToken),
            amount
        )
    {
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
        external onlyRole(RELAYER) isActive returns (uint256 amountWithdrawn)
    {
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

    function redeemBUIDLCircleFacility(uint256 usdcAmount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(LIMIT_BUIDL_REDEEM_CIRCLE, usdcAmount)
    {
        _approve(address(buidlRedeem.asset()), address(buidlRedeem), usdcAmount);

        proxy.doCall(
            address(buidlRedeem),
            abi.encodeCall(buidlRedeem.redeem, (usdcAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Ethena functions                                                               ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner) external onlyRole(RELAYER) isActive {
        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.setDelegatedSigner, (address(delegatedSigner)))
        );
    }

    function removeDelegatedSigner(address delegatedSigner) external onlyRole(RELAYER) isActive {
        proxy.doCall(
            address(ethenaMinter),
            abi.encodeCall(ethenaMinter.removeDelegatedSigner, (address(delegatedSigner)))
        );
    }

    // Note that Ethena's mint/redeem per-block limits include other users
    function prepareUSDeMint(uint256 usdcAmount)
        external onlyRole(RELAYER) isActive rateLimited(LIMIT_USDE_MINT, usdcAmount)
    {
        _approve(address(usdc), address(ethenaMinter), usdcAmount);
    }

    function prepareUSDeBurn(uint256 usdeAmount)
        external onlyRole(RELAYER) isActive rateLimited(LIMIT_USDE_BURN, usdeAmount)
    {
        _approve(address(usde), address(ethenaMinter), usdeAmount);
    }

    function cooldownAssetsSUSDe(uint256 usdeAmount)
        external onlyRole(RELAYER) isActive rateLimited(LIMIT_SUSDE_COOLDOWN, usdeAmount)
    {
        proxy.doCall(
            address(susde),
            abi.encodeCall(susde.cooldownAssets, (usdeAmount))
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function cooldownSharesSUSDe(uint256 susdeAmount)
        external
        onlyRole(RELAYER)
        isActive
        returns (uint256 cooldownAmount)
    {
        cooldownAmount = abi.decode(
            proxy.doCall(
                address(susde),
                abi.encodeCall(susde.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        rateLimits.triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, cooldownAmount);
    }

    function unstakeSUSDe() external onlyRole(RELAYER) isActive {
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
        onlyRole(RELAYER)
        isActive
        rateLimited(
            RateLimitHelpers.makeAssetKey(LIMIT_MAPLE_REDEEM, mapleToken),
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        )
    {
        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).requestRedeem, (shares, address(proxy)))
        );
    }

    function cancelMapleRedemption(address mapleToken, uint256 shares)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_MAPLE_REDEEM, mapleToken))
    {
        proxy.doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike(mapleToken).removeShares, (shares, address(proxy)))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Morpho functions                                                               ***/
    /**********************************************************************************************/

    function setSupplyQueueMorpho(address morphoVault, Id[] memory newSupplyQueue)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).setSupplyQueue, (newSupplyQueue))
        );
    }

    function updateWithdrawQueueMorpho(address morphoVault, uint256[] calldata indexes)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).updateWithdrawQueue, (indexes))
        );
    }

    function reallocateMorpho(address morphoVault, MarketAllocation[] calldata allocations)
        external
        onlyRole(RELAYER)
        isActive
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).reallocate, (allocations))
        );
    }

    /**********************************************************************************************/
    /*** Relayer Superstate functions                                                           ***/
    /**********************************************************************************************/

    function subscribeSuperstate(uint256 usdcAmount)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(LIMIT_SUPERSTATE_SUBSCRIBE, usdcAmount)
    {
        _approve(address(usdc), address(ustb), usdcAmount);

        proxy.doCall(
            address(ustb),
            abi.encodeCall(ustb.subscribe, (usdcAmount, address(usdc)))
        );
    }

    // NOTE: Rate limited outside of modifier because of tuple return
    function redeemSuperstate(uint256 ustbAmount) external onlyRole(RELAYER) isActive {
        ( uint256 usdcAmount, ) = superstateRedemption.calculateUsdcOut(ustbAmount);

        rateLimits.triggerRateLimitDecrease(LIMIT_SUPERSTATE_REDEEM, usdcAmount);

        _approve(address(ustb), address(superstateRedemption), ustbAmount);

        proxy.doCall(
            address(superstateRedemption),
            abi.encodeCall(superstateRedemption.redeem, (ustbAmount))
        );
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    function swapUSDSToUSDC(uint256 usdcAmount)
        external onlyRole(RELAYER) isActive rateLimited(LIMIT_USDS_TO_USDC, usdcAmount)
    {
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

    function swapUSDCToUSDS(uint256 usdcAmount)
        external onlyRole(RELAYER) isActive cancelRateLimit(LIMIT_USDS_TO_USDC, usdcAmount)
    {
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

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain)
        external
        onlyRole(RELAYER)
        isActive
        rateLimited(LIMIT_USDC_TO_CCTP, usdcAmount)
        rateLimited(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            usdcAmount
        )
    {
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
    /*** Internal helper functions                                                              ***/
    /**********************************************************************************************/

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

}

