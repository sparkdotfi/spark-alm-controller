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
        address burnToken
    )
        external
        returns (uint64 nonce);

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
        uint64  indexed nonce,
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

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setMintRecipient(
        mapping (uint32 => bytes32) storage mintRecipients,
        bytes32                             recipient,
        uint32                              destinationDomain
    ) external {
        emit MintRecipientSet(destinationDomain, mintRecipients[destinationDomain] = recipient);
    }

    function transferUSDCToCCTP(
        address proxy,
        address rateLimits,
        address cctp,
        address usdc,
        bytes32 mintRecipient,
        uint32  destinationDomain,
        uint256 usdcAmount
    )
        external
    {
        _decreaseRateLimit(rateLimits, LIMIT_TO_CCTP, usdcAmount);

        _decreaseRateLimit(
            rateLimits,
            makeUint32Key(LIMIT_TO_DOMAIN, destinationDomain),
            usdcAmount
        );

        require(mintRecipient != 0, "CCTPLib/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(proxy, usdc, cctp, usdcAmount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit =
            ICCTPTokenMinterLike(ICCTPLike(cctp).localMinter()).burnLimitsPerMessage(usdc);

        require(burnLimit > 0, "CCTPLib/burn-limit-not-set");

        // Copy the variable to avoid modifying the original in memory.
        uint256 usdcAmountRemaining = usdcAmount;

        while (usdcAmountRemaining > 0) {
            uint256 amount = usdcAmountRemaining > burnLimit ? burnLimit : usdcAmountRemaining;

            _initiateCCTPTransfer(
                proxy,
                cctp,
                usdc,
                amount,
                mintRecipient,
                destinationDomain
            );

            usdcAmountRemaining -= amount;
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: As USDC is the only asset transferred using CCTP, `ApproveLib` is unnecessary.
    function _approve(address proxy, address token, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _initiateCCTPTransfer(
        address proxy,
        address cctp,
        address usdc,
        uint256 usdcAmount,
        bytes32 mintRecipient,
        uint32  destinationDomain
    )
        internal
    {
        uint64 nonce = abi.decode(
            IALMProxy(proxy).doCall(
                cctp,
                abi.encodeCall(
                    ICCTPLike.depositForBurn,
                    (
                        usdcAmount,
                        destinationDomain,
                        mintRecipient,
                        usdc
                    )
                )
            ),
            (uint64)
        );

        emit CCTPTransferInitiated(nonce, destinationDomain, mintRecipient, usdcAmount);
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address rateLimits, bytes32 key, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
