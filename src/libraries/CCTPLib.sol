// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

    // NOTE: Used to track individual transfers for off-chain processing of CCTP transactions.
    event CCTPTransferInitiated(
        uint64  indexed nonce,
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256         usdcAmount
    );

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transferUSDCToCCTP(TransferUSDCToCCTPParams calldata params) external {
        _rateLimited(params.rateLimits, params.cctpRateLimitId, params.usdcAmount);

        _rateLimited(
            params.rateLimits,
            RateLimitHelpers.makeUint32Key(params.domainRateLimitId, params.destinationDomain),
            params.usdcAmount
        );

        require(params.mintRecipient != 0, "MC/domain-not-configured");

        // Approve USDC to CCTP from the proxy (assumes the proxy has enough USDC).
        _approve(params.proxy, address(params.usdc), address(params.cctp), params.usdcAmount);

        // If amount is larger than limit it must be split into multiple calls.
        uint256 burnLimit = params.cctp.localMinter().burnLimitsPerMessage(address(params.usdc));

        require(burnLimit > 0, "MC/burn-limit-not-set"); // Will test this with vm.mock.

        // This variable will get reduced in the loop below.
        uint256 usdcAmountTemp = params.usdcAmount;

        while (usdcAmountTemp > 0) {
            uint256 amount = usdcAmountTemp > burnLimit ? burnLimit : usdcAmountTemp;

            _initiateCCTPTransfer(
                params.proxy,
                params.cctp,
                params.usdc,
                amount,
                params.mintRecipient,
                params.destinationDomain
            );

            usdcAmountTemp -= amount;
        }
    }

    /**********************************************************************************************/
    /*** Relayer helper functions                                                               ***/
    /**********************************************************************************************/

    // NOTE: As USDC is the only asset transferred using CCTP, `_forceApprove` logic is unnecessary.
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
