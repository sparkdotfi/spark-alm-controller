// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeUint32Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { ICCTPFacet } from "./ICCTPFacet.sol";

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
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CCTPFacet.v1
    struct FacetStorage {
        uint256 maxFeeCap;
        mapping (uint32 destinationDomain => bytes32 mintRecipient) mintRecipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.CCTPFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x53491f888384d20e0e997ee4365903f1b7563469d6dee4850bb24641e6d23800;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant override LIMIT_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");

    bytes32 public constant override DESTINATION_CALLER     = 0;      // 0 means anyone can relay
    uint256 public constant override MAX_FEE                = 0;      // 0 for standard burns (no fast burn fee)
    uint32  public constant override MAX_FINALITY_THRESHOLD = 2_000;  // 2_000 for standard (finalized) messages

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override cctp;
    address public immutable override usdc;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address cctp_, address usdc_) {
        require(cctp_ != address(0), "CCTPFacet/zero-cctp");
        require(usdc_ != address(0), "CCTPFacet/zero-usdc");

        cctp = cctp_;
        usdc = usdc_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setMaxFeeCap(uint256 feeCap)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPMaxFeeCapSet(_getFacetStorage().maxFeeCap = feeCap);
    }

    function setMintRecipient(uint32 destinationDomain, bytes32 recipient)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit CCTPMintRecipientSet(
            destinationDomain,
            _getFacetStorage().mintRecipients[destinationDomain] = recipient
        );
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function transfer(uint256 amount, uint32 destinationDomain)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _transfer(amount, MAX_FEE, destinationDomain);
    }

    function transferWithFee(uint256 amount, uint256 maxFee, uint32 destinationDomain)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _transfer(amount, maxFee, destinationDomain);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function maxFeeCap() external view override returns (uint256) {
        return _getFacetStorage().maxFeeCap;
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getMintRecipient(uint32 destinationDomain) external view override returns (bytes32) {
        return _getFacetStorage().mintRecipients[destinationDomain];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _transfer(uint256 amount, uint256 maxFee, uint32 destinationDomain) internal {
        _decreaseRateLimit(LIMIT_TO_CCTP,                                     amount);
        _decreaseRateLimit(makeUint32Key(LIMIT_TO_DOMAIN, destinationDomain), amount);

        FacetStorage storage $ = _getFacetStorage();

        bytes32 recipient = $.mintRecipients[destinationDomain];

        require(recipient != 0,        "CCTPFacet/domain-not-configured");
        require(maxFee <= $.maxFeeCap, "CCTPFacet/max-fee-exceeds-cap");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, cctp, amount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit =
            ICCTPTokenMinterLike(ICCTPLike(cctp).localMinter()).burnLimitsPerMessage(usdc);

        while (amount > 0) {
            uint256 transferAmount = amount > burnLimit ? burnLimit : amount;

            // NOTE: When `amount` is split into chunks, the last chunk may be
            //       smaller than maxFee causing a revert.
            require(maxFee < transferAmount, "CCTPFacet/incorrect-max-fee");

            _initiateTransfer(transferAmount, maxFee, recipient, destinationDomain);

            amount -= transferAmount;
        }
    }

    // NOTE: As USDC is the only asset transferred using CCTP, `ApproveLib` is unnecessary.
    function _approve(address token, address spender, uint256 amount) internal {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            token,
            abi.encodeCall(IERC20Like.approve, (spender, amount))
        );
    }

    function _initiateTransfer(
        uint256 amount,
        uint256 maxFee,
        bytes32 mintRecipient,
        uint32  destinationDomain
    )
        internal
    {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            cctp,
            abi.encodeCall(
                ICCTPLike.depositForBurn,
                (
                    amount,
                    destinationDomain,
                    mintRecipient,
                    usdc,
                    DESTINATION_CALLER,
                    maxFee,
                    MAX_FINALITY_THRESHOLD
                )
            )
        );

        emit CCTPTransferInitiated(destinationDomain, mintRecipient, amount);
    }

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
