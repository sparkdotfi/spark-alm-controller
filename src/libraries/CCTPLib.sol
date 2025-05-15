// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { ICCTPLike }   from "../interfaces/CCTPInterfaces.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library CCTPLib {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct TransferUSDCToCCTPParams {
        IALMProxy   proxy;
        IRateLimits rateLimits;
        ICCTPLike   cctp;
        IERC20      usdc;
        bytes32     domainRateLimitId;
        bytes32     cctpRateLimitId;
        bytes32     mintRecipient;
        uint32      destinationDomain;
        uint256     usdcAmount;
    }

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

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(TransferUSDCToCCTPParams calldata params) external {
        _rateLimited(params.rateLimits, params.cctpRateLimitId, params.usdcAmount);
        _rateLimited(
            params.rateLimits,
            RateLimitHelpers.makeDomainKey(params.domainRateLimitId, params.destinationDomain),
            params.usdcAmount
        );

        require(params.mintRecipient != 0, "MainnetController/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC)
        _approve(params.proxy, address(params.usdc), address(params.cctp), params.usdcAmount);

        // If amount is larger than limit it must be split into multiple calls
        uint256 burnLimit = params.cctp.localMinter().burnLimitsPerMessage(address(params.usdc));

        // This variable will get reduced in the loop below
        uint256 usdcAmountTemp = params.usdcAmount;

        while (usdcAmountTemp > burnLimit) {
            _initiateCCTPTransfer(
                params.proxy,
                params.cctp,
                params.usdc,
                burnLimit,
                params.mintRecipient,
                params.destinationDomain
            );
            usdcAmountTemp -= burnLimit;
        }

        // Send remaining amount (if any)
        if (usdcAmountTemp > 0) {
            _initiateCCTPTransfer(
                params.proxy,
                params.cctp,
                params.usdc,
                usdcAmountTemp,
                params.mintRecipient,
                params.destinationDomain
            );
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: As USDC is the only asset transferred using CCTP, _forceApprove logic is unnecessary.
    function _approve(
        IALMProxy proxy,
        address   token,
        address   spender,
        uint256   amount
    )
        internal
    {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _initiateCCTPTransfer(
        IALMProxy proxy,
        ICCTPLike cctp,
        IERC20    usdc,
        uint256   usdcAmount,
        bytes32   mintRecipient,
        uint32    destinationDomain
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

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/
    
    function _rateLimited(IRateLimits rateLimits, bytes32 key, uint256 amount) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
