// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

import { makeUint32Key } from "../RateLimitHelpers.sol";

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

// NOTE: This library makes the assumption that the token is USDC.
library CCTPLib {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    // NOTE: Used to track individual transfers for off-chain processing of CCTP transactions.
    event CCTPTransferInitiated(
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256         usdcAmount
    );

    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 indexed mintRecipient);

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 public constant LIMIT_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");

    bytes32 public constant DESTINATION_CALLER     = 0;      // 0 means anyone can relay
    uint256 public constant MAX_FEE                = 0;      // 0 for standard burns (no fast burn fee)
    uint32  public constant MAX_FINALITY_THRESHOLD = 2_000;  // 2_000 for standard (finalized) messages

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setMintRecipient(
        mapping (uint32 => bytes32) storage mintRecipients,
        bytes32 recipient,
        uint32  destinationDomain
    ) external {
        emit MintRecipientSet(destinationDomain, mintRecipients[destinationDomain] = recipient);
    }

    function transfer(
        address proxy,
        address rateLimits,
        address cctp,
        address usdc,
        uint32  destinationDomain,
        uint256 usdcAmount,
        uint256 maxFee,
        uint256 cctpMaxFeeCap,
        mapping (uint32 => bytes32) storage mintRecipients
    )
        external
    {
        _decreaseRateLimit(rateLimits, LIMIT_TO_CCTP, usdcAmount);

        _decreaseRateLimit(
            rateLimits,
            makeUint32Key(LIMIT_TO_DOMAIN, destinationDomain),
            usdcAmount
        );

        bytes32 recipient = mintRecipients[destinationDomain];

        require(recipient != 0,          "CCTPLib/domain-not-configured");
        require(maxFee <= cctpMaxFeeCap, "CCTPLib/max-fee-exceeds-cap");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, proxy, cctp, usdcAmount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit =
            ICCTPTokenMinterLike(ICCTPLike(cctp).localMinter()).burnLimitsPerMessage(usdc);

        while (usdcAmount > 0) {
            uint256 amount = usdcAmount > burnLimit ? burnLimit : usdcAmount;

            // NOTE: When amount is split into chunks, the last chunk may be
            //       smaller than maxFee causing a revert.
            require(maxFee < amount, "CCTPLib/incorrect-max-fee");

            _initiateTransfer(
                proxy,
                cctp,
                usdc,
                amount,
                maxFee,
                recipient,
                destinationDomain
            );

            usdcAmount -= amount;
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: As USDC is the only asset transferred using CCTP, `ApproveLib` is unnecessary.
    function _approve(address token, address proxy, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _initiateTransfer(
        address proxy,
        address cctp,
        address usdc,
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

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address rateLimits, bytes32 key, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
