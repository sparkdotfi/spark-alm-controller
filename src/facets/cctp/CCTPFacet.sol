// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeUint32Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

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

contract CCTPFacet is ICCTPFacet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.CCTPFacet.v1
    struct FacetStorage {
        mapping (uint32 destinationDomain => DomainParameters parameters) domainParameters;
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

    bytes32 internal constant _LIMIT_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 internal constant _LIMIT_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");

    uint256 internal constant _ONE_HUNDRED_PERCENT = 10_000;

    /// @inheritdoc ICCTPFacet
    bytes32 public constant override DESTINATION_CALLER = 0;  // 0 means anyone can relay

    /// @inheritdoc ICCTPFacet
    uint32 public constant override MIN_FINALITY_THRESHOLD = 2_000;  // 2_000 for standard (finalized) messages

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ICCTPFacet
    address public immutable override cctp;

    /// @inheritdoc ICCTPFacet
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

    /// @inheritdoc ICCTPFacet
    function setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    )
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(recipient != bytes32(0), "CCTPFacet/zero-recipient");

        require(minFeeCapRate <= maxFeeCapRate,       "CCTPFacet/min-fee-cap-rate-too-high");
        require(maxFeeCapRate < _ONE_HUNDRED_PERCENT, "CCTPFacet/max-fee-cap-rate-too-high");

        _getFacetStorage().domainParameters[destinationDomain] = DomainParameters(
            recipient,
            minFeeCapRate,
            maxFeeCapRate
        );

        emit CCTPDomainParametersSet(destinationDomain, recipient, minFeeCapRate, maxFeeCapRate);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc ICCTPFacet
    function transfer(uint256 amount, uint32 destinationDomain, uint64 feeCapRate)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(toCCTPRateLimitKey(),                       amount);
        _decreaseRateLimit(getToDomainRateLimitKey(destinationDomain), amount);

        DomainParameters storage params = _getFacetStorage().domainParameters[destinationDomain];

        bytes32 recipient     = params.mintRecipient;
        uint32  minFeeCapRate = params.minFeeCapRate;
        uint32  maxFeeCapRate = params.maxFeeCapRate;

        require(recipient != 0,              "CCTPFacet/domain-not-configured");
        require(feeCapRate >= minFeeCapRate, "CCTPFacet/fee-cap-rate-too-low");
        require(feeCapRate <= maxFeeCapRate, "CCTPFacet/fee-cap-rate-too-high");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, cctp, amount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit =
            ICCTPTokenMinterLike(ICCTPLike(cctp).localMinter()).burnLimitsPerMessage(usdc);

        while (amount > 0) {
            uint256 transferAmount = amount > burnLimit ? burnLimit : amount;
            uint256 maxFee         = (transferAmount * feeCapRate) / _ONE_HUNDRED_PERCENT;

            _initiateTransfer(transferAmount, maxFee, recipient, destinationDomain);

            amount -= transferAmount;
        }

        // Clear approvals
        _approve(usdc, cctp, 0);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc ICCTPFacet
    function toCCTPRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_TO_CCTP;
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ICCTPFacet
    function getDomainParameters(uint32 destinationDomain)
        external
        view
        override
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate)
    {
        DomainParameters storage params = _getFacetStorage().domainParameters[destinationDomain];

        return (params.mintRecipient, params.minFeeCapRate, params.maxFeeCapRate);
    }

    /// @inheritdoc ICCTPFacet
    function getToDomainRateLimitKey(uint32 destinationDomain)
        public
        pure
        override
        returns (bytes32)
    {
        return makeUint32Key(_LIMIT_TO_DOMAIN, destinationDomain);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

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
                    MIN_FINALITY_THRESHOLD
                )
            )
        );

        emit CCTPTransferInitiated(destinationDomain, mintRecipient, amount, maxFee);
    }

}
