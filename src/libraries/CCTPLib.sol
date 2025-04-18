// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { ICCTPLike }   from "../interfaces/CCTPInterfaces.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

library CCTPLib {

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

    function transferUSDCToCCTPLib(
        uint256     usdcAmount,
        uint32      destinationDomain,
        IALMProxy   proxy,
        IRateLimits rateLimits,
        bytes32     LIMIT_USDC_TO_DOMAIN,
        bytes32     LIMIT_USDC_TO_CCTP,
        bytes32     mintRecipient,
        ICCTPLike   cctp,
        IERC20      usdc
    ) external {
        _rateLimited(LIMIT_USDC_TO_CCTP, usdcAmount, rateLimits);
        _rateLimited(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            usdcAmount,
            rateLimits
        );

        require(mintRecipient != 0, "MainnetController/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC)
        _approve(address(usdc), address(cctp), usdcAmount, proxy);

        // If amount is larger than limit it must be split into multiple calls
        uint256 burnLimit = cctp.localMinter().burnLimitsPerMessage(address(usdc));

        while (usdcAmount > burnLimit) {
            _initiateCCTPTransfer(burnLimit, destinationDomain, mintRecipient, proxy, cctp, usdc);
            usdcAmount -= burnLimit;
        }

        // Send remaining amount (if any)
        if (usdcAmount > 0) {
            _initiateCCTPTransfer(usdcAmount, destinationDomain, mintRecipient, proxy, cctp, usdc);
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    function _approve(
        address   token,
        address   spender,
        uint256   amount,
        IALMProxy proxy
    )
        internal
    {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _initiateCCTPTransfer(
        uint256   usdcAmount,
        uint32    destinationDomain,
        bytes32   mintRecipient,
        IALMProxy proxy,
        ICCTPLike cctp,
        IERC20    usdc
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

    function _rateLimited(bytes32 key, uint256 amount, IRateLimits rateLimits) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

}
