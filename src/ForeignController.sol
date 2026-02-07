// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { OptionsBuilder } from "../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { ReentrancyGuard }         from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { IPSM3 } from "../lib/spark-psm/src/interfaces/IPSM3.sol";

import { AaveLib }          from "./libraries/AaveLib.sol";
import { ApproveLib }       from "./libraries/ApproveLib.sol";
import { CCTPLib }          from "./libraries/CCTPLib.sol";
import { ERC4626Lib }       from "./libraries/ERC4626Lib.sol";
import { TransferAssetLib } from "./libraries/TransferAssetLib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface ISparkVaultLike {

    function take(uint256 assetAmount) external;

}

contract ForeignController is ReentrancyGuard, AccessControlEnumerable {

    using OptionsBuilder for bytes;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_4626_DEPOSIT       = ERC4626Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_4626_WITHDRAW      = ERC4626Lib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_AAVE_DEPOSIT       = AaveLib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_AAVE_WITHDRAW      = AaveLib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_ASSET_TRANSFER     = TransferAssetLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_PSM_DEPOSIT        = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 public constant LIMIT_PSM_WITHDRAW       = keccak256("LIMIT_PSM_WITHDRAW");
    bytes32 public constant LIMIT_SPARK_VAULT_TAKE   = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 public constant LIMIT_USDC_TO_CCTP       = CCTPLib.LIMIT_TO_CCTP;
    bytes32 public constant LIMIT_USDC_TO_DOMAIN     = CCTPLib.LIMIT_TO_DOMAIN;

    IALMProxy   public immutable proxy;
    address     public immutable cctp;
    IPSM3       public immutable psm;
    IRateLimits public immutable rateLimits;

    address public immutable usdc;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationDomain     => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;

    // ERC4626 exchange rate thresholds (1e36 precision)
    mapping(address token => uint256 maxExchangeRate) public maxExchangeRates;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address psm_,
        address usdc_,
        address cctp_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = IALMProxy(proxy_);
        rateLimits = IRateLimits(rateLimits_);
        psm        = IPSM3(psm_);
        usdc       = usdc_;
        cctp       = cctp_;
    }

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier rateLimited(bytes32 key, uint256 amount) {
        rateLimits.triggerRateLimitDecrease(key, amount);
        _;
    }

    modifier rateLimitedAddress(bytes32 key, address asset, uint256 amount) {
        rateLimits.triggerRateLimitDecrease(RateLimitHelpers.makeAddressKey(key, asset), amount);
        _;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "FC/pool-zero-address");

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

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

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ERC4626Lib.setMaxExchangeRate(maxExchangeRates, token, shares, maxExpectedAssets);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
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
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_PSM_DEPOSIT, asset, amount)
        returns (uint256 shares)
    {
        // Approve `asset` to PSM from the proxy (assumes the proxy has enough `asset`).
        ApproveLib.approve(asset, address(proxy), address(psm), amount);

        // Deposit `amount` of `asset` in the PSM, decode the result to get `shares`.
        return abi.decode(
            proxy.doCall(
                address(psm),
                abi.encodeCall(
                    psm.deposit,
                    (asset, address(proxy), amount)
                )
            ),
            (uint256)
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function withdrawPSM(address asset, uint256 maxAmount)
        external nonReentrant onlyRole(RELAYER) returns (uint256 assetsWithdrawn)
    {
        // Withdraw up to `maxAmount` of `asset` in the PSM, decode the result
        // to get `assetsWithdrawn` (assumes the proxy has enough PSM shares).
        assetsWithdrawn = abi.decode(
            proxy.doCall(
                address(psm),
                abi.encodeCall(
                    psm.withdraw,
                    (asset, address(proxy), maxAmount)
                )
            ),
            (uint256)
        );

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAddressKey(LIMIT_PSM_WITHDRAW, asset),
            assetsWithdrawn
        );
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
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_SPARK_VAULT_TAKE, sparkVault, assetAmount)
    {
        // Take assets from the vault
        proxy.doCall(
            sparkVault,
            abi.encodeCall(ISparkVaultLike.take, (assetAmount))
        );
    }

}
