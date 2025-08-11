// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAToken }            from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";
import { IPool as IAavePool } from "aave-v3-origin/src/core/contracts/interfaces/IPool.sol";

import { IMetaMorpho, Id, MarketAllocation } from "metamorpho/interfaces/IMetaMorpho.sol";

import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IERC20 }   from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { IPSM3 } from "spark-psm/src/interfaces/IPSM3.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { ICCTPLike }   from "./interfaces/CCTPInterfaces.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { ICentrifugeV3VaultLike, IAsyncRedeemManagerLike, ISpokeLike } from "./interfaces/CentrifugeInterfaces.sol";

import "./interfaces/ILayerZero.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { RateLimitHelpers } from "./RateLimitHelpers.sol";

interface IATokenWithPool is IAToken {
    function POOL() external view returns(address);
}

contract ForeignController is AccessControl {

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

    event CentrifugeRecipientSet(uint16 indexed destinationCentrifugeId, bytes32 recipient);

    event LayerZeroRecipientSet(uint32 indexed destinationEndpointId, bytes32 layerZeroRecipient);

    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);

    event RelayerRemoved(address indexed relayer);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_4626_DEPOSIT        = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant LIMIT_4626_WITHDRAW       = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 public constant LIMIT_7540_DEPOSIT        = keccak256("LIMIT_7540_DEPOSIT");
    bytes32 public constant LIMIT_7540_REDEEM         = keccak256("LIMIT_7540_REDEEM");
    bytes32 public constant LIMIT_AAVE_DEPOSIT        = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant LIMIT_AAVE_WITHDRAW       = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 public constant LIMIT_CENTRIFUGE_TRANSFER = keccak256("LIMIT_CENTRIFUGE_TRANSFER");
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER  = keccak256("LIMIT_LAYERZERO_TRANSFER");
    bytes32 public constant LIMIT_PSM_DEPOSIT         = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 public constant LIMIT_PSM_WITHDRAW        = keccak256("LIMIT_PSM_WITHDRAW");
    bytes32 public constant LIMIT_USDC_TO_CCTP        = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_USDC_TO_DOMAIN      = keccak256("LIMIT_USDC_TO_DOMAIN");

    uint256 internal constant CENTRIFUGE_REQUEST_ID = 0;

    IALMProxy   public immutable proxy;
    ICCTPLike   public immutable cctp;
    IPSM3       public immutable psm;
    IRateLimits public immutable rateLimits;

    IERC20 public immutable usdc;

    mapping(uint32 destinationDomain       => bytes32 mintRecipient)      public mintRecipients;
    mapping(uint32 destinationEndpointId   => bytes32 layerZeroRecipient) public layerZeroRecipients;
    mapping(uint16 destinationCentrifugeId => bytes32 recipient)          public centrifugeRecipients;

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

    modifier rateLimitedAsset(bytes32 key, address asset, uint256 amount) {
        rateLimits.triggerRateLimitDecrease(RateLimitHelpers.makeAssetKey(key, asset), amount);
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

    function setCentrifugeRecipient(uint16 destinationCentrifugeId, bytes32 recipient)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        centrifugeRecipients[destinationCentrifugeId] = recipient;
        emit CentrifugeRecipientSet(destinationCentrifugeId, recipient);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer PSM functions                                                                  ***/
    /**********************************************************************************************/

    function depositPSM(address asset, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAsset(LIMIT_PSM_DEPOSIT, asset, amount)
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
            RateLimitHelpers.makeAssetKey(LIMIT_PSM_WITHDRAW, asset),
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
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
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
        rateLimitedAsset(LIMIT_4626_DEPOSIT, token, amount)
        returns (uint256 shares)
    {
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
    }

    function withdrawERC4626(address token, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAsset(LIMIT_4626_WITHDRAW, token, amount)
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
        rateLimitedAsset(LIMIT_7540_DEPOSIT, token, amount)
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
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token))
    {

        uint256 shares = IERC7540(token).maxMint(address(proxy));

        // Claim shares from the vault to the proxy
        proxy.doCall(
            token,
            abi.encodeCall(IERC4626(token).mint, (shares, address(proxy)))
        );
    }

    function requestRedeemERC7540(address token, uint256 shares)
        external
        onlyRole(RELAYER)
        rateLimitedAsset(LIMIT_7540_REDEEM, token, IERC7540(token).convertToAssets(shares))
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
    /*** Relayer Centrifuge functions                                                           ***/
    /**********************************************************************************************/

    // NOTE: These cancelation methods are compatible with ERC-7887

    function cancelCentrifugeDepositRequest(address token)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token))
    {
        // NOTE: While the cancelation is pending, no new deposit request can be submitted
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).cancelDepositRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy))
            )
        );
    }

    function claimCentrifugeCancelDepositRequest(address token)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_DEPOSIT, token))
    {
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelDepositRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy), address(proxy))
            )
        );
    }

    function cancelCentrifugeRedeemRequest(address token)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token))
    {
        // NOTE: While the cancelation is pending, no new redeem request can be submitted
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).cancelRedeemRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy))
            )
        );
    }

    function claimCentrifugeCancelRedeemRequest(address token)
        external
        onlyRole(RELAYER)
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_7540_REDEEM, token))
    {
        proxy.doCall(
            token,
            abi.encodeCall(
                ICentrifugeV3VaultLike(token).claimCancelRedeemRequest,
                (CENTRIFUGE_REQUEST_ID, address(proxy), address(proxy))
            )
        );
    }

    function transferSharesCentrifuge(
        address token,
        uint128 amount,
        uint16  destinationCentrifugeId
    )
        external payable
    {
        _checkRole(RELAYER);
        _rateLimited(
            keccak256(abi.encode(LIMIT_CENTRIFUGE_TRANSFER, token, destinationCentrifugeId)),
            amount
        );

        bytes32 recipient = centrifugeRecipients[destinationCentrifugeId];
        require(recipient != 0, "ForeignController/centrifuge-id-not-configured");

        ICentrifugeV3VaultLike centrifugeVault = ICentrifugeV3VaultLike(token);

        address spoke = IAsyncRedeemManagerLike(centrifugeVault.manager()).spoke();

        // Initiate cross-chain transfer via the specific spoke address
        proxy.doCallWithValue{value: msg.value}(
            spoke,
            abi.encodeCall(
                ISpokeLike(spoke).crosschainTransferShares,
                (
                    destinationCentrifugeId,
                    centrifugeVault.poolId(),
                    centrifugeVault.scId(),
                    recipient,
                    amount,
                    0
                )
            ),
            msg.value
        );
    }

    /**********************************************************************************************/
    /*** Relayer Aave functions                                                                 ***/
    /**********************************************************************************************/

    function depositAave(address aToken, uint256 amount)
        external
        onlyRole(RELAYER)
        rateLimitedAsset(LIMIT_AAVE_DEPOSIT, aToken, amount)
    {
        IERC20    underlying = IERC20(IATokenWithPool(aToken).UNDERLYING_ASSET_ADDRESS());
        IAavePool pool       = IAavePool(IATokenWithPool(aToken).POOL());

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        _approve(address(underlying), address(pool), amount);

        // Deposit underlying into Aave pool, proxy receives aTokens.
        proxy.doCall(
            address(pool),
            abi.encodeCall(pool.supply, (address(underlying), amount, address(proxy), 0))
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
            RateLimitHelpers.makeAssetKey(LIMIT_AAVE_WITHDRAW, aToken),
            amountWithdrawn
        );
    }

    /**********************************************************************************************/
    /*** Relayer Morpho functions                                                               ***/
    /**********************************************************************************************/

    function setSupplyQueueMorpho(address morphoVault, Id[] memory newSupplyQueue)
        external
        onlyRole(RELAYER)
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
        rateLimitExists(RateLimitHelpers.makeAssetKey(LIMIT_4626_DEPOSIT, morphoVault))
    {
        proxy.doCall(
            morphoVault,
            abi.encodeCall(IMetaMorpho(morphoVault).reallocate, (allocations))
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
