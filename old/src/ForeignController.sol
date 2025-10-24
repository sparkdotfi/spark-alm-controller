// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { IMetaMorpho, Id, MarketAllocation } from "metamorpho/interfaces/IMetaMorpho.sol";

import { AccessControlEnumerable } from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IERC20 }   from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { IPSM3 } from "spark-psm/src/interfaces/IPSM3.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { ICCTPLike }   from "./interfaces/CCTPInterfaces.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import  "./interfaces/ILayerZero.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
}

interface ISparkVaultLike {
    function take(uint256 assetAmount) external;
}

contract ForeignController is AccessControlEnumerable {

    using OptionsBuilder for bytes;

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

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_4626_DEPOSIT       = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant LIMIT_4626_WITHDRAW      = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public constant LIMIT_AAVE_DEPOSIT       = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant LIMIT_AAVE_WITHDRAW      = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public constant LIMIT_ASSET_TRANSFER     = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER = keccak256("LIMIT_LAYERZERO_TRANSFER");
    bytes32 public constant LIMIT_PSM_DEPOSIT        = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 public constant LIMIT_PSM_WITHDRAW       = keccak256("LIMIT_PSM_WITHDRAW");
    bytes32 public constant LIMIT_SPARK_VAULT_TAKE   = keccak256("LIMIT_SPARK_VAULT_TAKE");
    bytes32 public constant LIMIT_USDC_TO_CCTP       = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_USDC_TO_DOMAIN     = keccak256("LIMIT_USDC_TO_DOMAIN");

    IALMProxy   public immutable proxy;
    ICCTPLike   public immutable cctp;
    IPSM3       public immutable psm;
    IRateLimits public immutable rateLimits;

    IERC20 public immutable usdc;

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
        address psm_,
        address usdc_,
        address cctp_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = IALMProxy(proxy_);
        rateLimits = IRateLimits(rateLimits_);
        psm        = IPSM3(psm_);
        usdc       = IERC20(usdc_);
        cctp       = ICCTPLike(cctp_);
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

    modifier rateLimitExists(bytes32 key) {
        require(
            rateLimits.getRateLimitData(key).maxAmount > 0,
            "ForeignController/invalid-action"
        );
        _;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "ForeignController/pool-zero-address");

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

    function setMintRecipient(uint32 destinationDomain, bytes32 mintRecipient)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        mintRecipients[destinationDomain] = mintRecipient;
        emit MintRecipientSet(destinationDomain, mintRecipient);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 layerZeroRecipient)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        layerZeroRecipients[destinationEndpointId] = layerZeroRecipient;
        emit LayerZeroRecipientSet(destinationEndpointId, layerZeroRecipient);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount)
        external
        onlyRole(RELAYER)
    {
        _rateLimited(
            RateLimitHelpers.makeAddressAddressKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        bytes memory returnData = proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || abi.decode(returnData, (bool)),
            "ForeignController/transfer-failed"
        );
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_PSM_DEPOSIT, asset, amount)
        returns (uint256 shares)
    {
        // Approve `asset` to PSM from the proxy (assumes the proxy has enough `asset`).
        _approve(asset, address(psm), amount);

        // Deposit `amount` of `asset` in the PSM, decode the result to get `shares`.
        shares = abi.decode(
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
        external
        onlyRole(RELAYER)
        returns (uint256 assetsWithdrawn)
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
        onlyRole(RELAYER)
        rateLimited(LIMIT_USDC_TO_CCTP, usdcAmount)
        rateLimited(
            RateLimitHelpers.makeUint32Key(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            usdcAmount
        )
    {
        bytes32 mintRecipient = mintRecipients[destinationDomain];

        require(mintRecipient != 0, "ForeignController/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(address(usdc), address(cctp), usdcAmount);

        // If amount is larger than limit it must be split into multiple calls.
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
        //       approvalRequired == true. Add integration testing for this case before
        //       using in production.
        if (ILayerZero(oftAddress).approvalRequired()) {
            _approve(ILayerZero(oftAddress).token(), oftAddress, amount);
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
    /*** Relayer ERC4626 functions                                                              ***/
    /**********************************************************************************************/

    function depositERC4626(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_4626_DEPOSIT, token, amount)
        returns (uint256 shares)
    {
        require(maxSlippages[token] != 0, "ForeignController/max-slippage-not-set");

        // Note that whitelist is done by rate limits.
        IERC20 asset = IERC20(IERC4626(token).asset());

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        _approve(address(asset), token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares.
        shares = abi.decode(
            proxy.doCall(
                token,
                abi.encodeCall(IERC4626(token).deposit, (amount, address(proxy)))
            ),
            (uint256)
        );

        require(
            IERC4626(token).convertToAssets(shares) >= amount * maxSlippages[token] / 1e18,
            "ForeignController/slippage-too-high"
        );
    }

    function withdrawERC4626(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_4626_WITHDRAW, token, amount)
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

        rateLimits.triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(LIMIT_4626_DEPOSIT, token),
            amount
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function redeemERC4626(address token, uint256 shares)
        external
        onlyRole(RELAYER)
        returns (uint256 assets)
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
            RateLimitHelpers.makeAddressKey(LIMIT_4626_WITHDRAW, token),
            assets
        );
        rateLimits.triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(LIMIT_4626_DEPOSIT, token),
            assets
        );
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_AAVE_DEPOSIT, aToken, amount)
    {
        require(maxSlippages[aToken] != 0, "ForeignController/max-slippage-not-set");

        IERC20    underlying = IERC20(IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS());
        IAavePool pool       = IAavePool(IATokenWithPool(aToken).POOL());

        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(proxy));

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        _approve(address(underlying), address(pool), amount);

        // Deposit underlying into Aave pool, proxy receives aTokens.
        proxy.doCall(
            address(pool),
            abi.encodeCall(pool.supply, (address(underlying), amount, address(proxy), 0))
        );

        uint256 newATokens = IERC20(aToken).balanceOf(address(proxy)) - aTokenBalance;

        require(
            newATokens >= amount * maxSlippages[aToken] / 1e18,
            "ForeignController/slippage-too-high"
        );
    }

    // NOTE: !!! Rate limited at end of function !!!
    function withdrawAave(address aToken, uint256 amount)
        external
        onlyRole(RELAYER)
        returns (uint256 amountWithdrawn)
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
            RateLimitHelpers.makeAddressKey(LIMIT_AAVE_WITHDRAW, aToken),
            amountWithdrawn
        );

        rateLimits.triggerRateLimitIncrease(
            RateLimitHelpers.makeAddressKey(LIMIT_AAVE_DEPOSIT, aToken),
            amountWithdrawn
        );
    }

    /**********************************************************************************************/
    /*** Relayer Morpho functions                                                               ***/
    /**********************************************************************************************/

    function setSupplyQueueMorpho(address morphoVault, Id[] memory newSupplyQueue)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAddressKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).setSupplyQueue, (newSupplyQueue))
        );
    }

    function updateWithdrawQueueMorpho(address morphoVault, uint256[] calldata indexes)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAddressKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).updateWithdrawQueue, (indexes))
        );
    }

    function reallocateMorpho(address morphoVault, MarketAllocation[] calldata allocations)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAddressKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).reallocate, (allocations))
        );
    }

    /**********************************************************************************************/
    /*** Spark Vault functions                                                                  ***/
    /**********************************************************************************************/

    function takeFromSparkVault(address sparkVault, uint256 assetAmount)
        external
        onlyRole(RELAYER)
        rateLimitedAddress(LIMIT_SPARK_VAULT_TAKE, sparkVault, assetAmount)
    {
        // Take assets from the vault
        proxy.doCall(
            sparkVault,
            abi.encodeCall(ISparkVaultLike.take, (assetAmount))
        );
    }

    /**********************************************************************************************/
    /*** Internal helper functions                                                              ***/
    /**********************************************************************************************/

    // NOTE: This logic was inspired by OpenZeppelin's forceApprove in SafeERC20 library
    function _approve(address token, address spender, uint256 amount) internal {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token
        ( bool success, bytes memory data )
            = address(proxy).call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        bytes memory approveCallReturnData;

        if (success) {
            // Data is the ABI-encoding of the approve call bytes return data, need to
            // decode it first
            approveCallReturnData = abi.decode(data, (bytes));
            // Approve was successful if 1) no return value or 2) true return value
            if (approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool))) {
                return;
            }
        }

        // If call was unsuccessful, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));

        approveCallReturnData = proxy.doCall(token, approveData);

        // Revert if approve returns false
        require(
            approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool)),
            "ForeignController/approve-failed"
        );
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

    function _rateLimited(bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
