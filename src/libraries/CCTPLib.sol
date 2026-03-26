// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { ICCTPFacet }  from "../interfaces/facets/ICCTPFacet.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeUint32Key } from "../RateLimitHelpers.sol";

import { FacetBase } from "./FacetBase.sol";

interface ICCTPLike {

    function depositForBurn(
        uint256 amount,
        uint32  destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32  minFinalityThreshold
    ) external;

    function localMinter() external view returns (address);

}

interface ICCTPTokenMinterLike {

    function burnLimitsPerMessage(address) external view returns (uint256);

}

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

}

// NOTE: This contract makes the assumption that the token is USDC.
contract CCTPFacet is ICCTPFacet, FacetBase {

    /**********************************************************************************************/
    /*** CCTPFacet Storage Domain                                                               ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CCTPFacet
    struct FacetStorage {
        uint256 maxFeeCap;
        mapping(uint32 destinationDomain => bytes32 mintRecipient) mintRecipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CCTPFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xd2297bc3b0b57b4cc880bf81d7f396bae29a02c9b84df07ff5f86bd65479da00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");

    bytes32 public constant DESTINATION_CALLER     = 0;      // 0 means anyone can relay
    uint256 public constant MAX_FEE                = 0;      // 0 for standard burns (no fast burn fee)
    uint32  public constant MAX_FINALITY_THRESHOLD = 2_000;  // 2_000 for standard (finalized) messages

    address public immutable cctp;
    address public immutable usdc;

    constructor(address cctp_, address usdc_) {
        cctp = cctp_;
        usdc = usdc_;
    }

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function setMaxFeeCap(uint256 maxFeeCap)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPMaxFeeCapSet(_getFacetStorage().maxFeeCap = maxFeeCap);
    }

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPMintRecipientSet(
            destinationDomain,
            _getFacetStorage().mintRecipients[destinationDomain] = recipient
        );
    }

    function transfer(uint256 usdcAmount, uint32 destinationDomain)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _transfer(usdcAmount, MAX_FEE, destinationDomain);
    }

    function transferWithFee(uint256 usdcAmount, uint256 maxFee, uint32 destinationDomain)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _transfer(usdcAmount, maxFee, destinationDomain);
    }

    /**********************************************************************************************/
    /*** Public view/pure functions                                                             ***/
    /**********************************************************************************************/

    function getMaxFeeCap() external view returns (uint256) {
        return _getFacetStorage().maxFeeCap;
    }

    function getMintRecipient(uint32 destinationDomain) external view returns (bytes32) {
        return _getFacetStorage().mintRecipients[destinationDomain];
    }

    /**********************************************************************************************/
    /*** Internal interactive functions                                                         ***/
    /**********************************************************************************************/

    function _transfer(uint256 usdcAmount, uint256 maxFee, uint32 destinationDomain) internal {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy      = $.proxy;
        address rateLimits = $.rateLimits;

        _decreaseRateLimit(rateLimits, LIMIT_TO_CCTP, usdcAmount);

        _decreaseRateLimit(
            rateLimits,
            makeUint32Key(LIMIT_TO_DOMAIN, destinationDomain),
            usdcAmount
        );

        FacetStorage storage fs = _getFacetStorage();

        bytes32 recipient = fs.mintRecipients[destinationDomain];

        require(recipient != 0,         "CCTPFacet/domain-not-configured");
        require(maxFee <= fs.maxFeeCap, "CCTPFacet/max-fee-exceeds-cap");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, proxy, cctp, usdcAmount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit =
            ICCTPTokenMinterLike(ICCTPLike(cctp).localMinter()).burnLimitsPerMessage(usdc);

        while (usdcAmount > 0) {
            uint256 amount = usdcAmount > burnLimit ? burnLimit : usdcAmount;

            // NOTE: When amount is split into chunks, the last chunk may be
            //       smaller than maxFee causing a revert.
            require(maxFee < amount, "CCTPFacet/incorrect-max-fee");

            _initiateTransfer(
                proxy,
                amount,
                maxFee,
                recipient,
                destinationDomain
            );

            usdcAmount -= amount;
        }
    }

    // NOTE: As USDC is the only asset transferred using CCTP, `ApproveLib` is unnecessary.
    function _approve(address token, address proxy, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _initiateTransfer(
        address proxy,
        uint256 usdcAmount,
        uint256 maxFee,
        bytes32 mintRecipient,
        uint32  destinationDomain
    )
        internal
    {
        IALMProxy(proxy).doCall(
            cctp,
            abi.encodeCall(
                ICCTPLike.depositForBurn,
                (
                    usdcAmount,
                    destinationDomain,
                    mintRecipient,
                    usdc,
                    DESTINATION_CALLER,
                    maxFee,
                    MAX_FINALITY_THRESHOLD
                )
            )
        );

        emit CCTPTransferInitiated(destinationDomain, mintRecipient, usdcAmount);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
