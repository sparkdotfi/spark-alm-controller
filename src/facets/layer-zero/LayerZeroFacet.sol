// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    OptionsBuilder
} from "../../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { ApproveLib }           from "../../libraries/ApproveLib.sol";
import { makeAddressUint32Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { ILayerZeroFacet } from "./ILayerZeroFacet.sol";

interface ILayerZeroLike {

    struct MessagingFee {
        uint256 nativeFee;  // Gas amount in native gas token.
        uint256 lzTokenFee; // Gas amount in ZRO token.
    }

    struct MessagingReceipt {
        bytes32      guid;
        uint64       nonce;
        MessagingFee fee;
    }

    /**
     * @notice Struct representing OFT fee details.
     * @notice Future proof mechanism to provide a standardized way to communicate fees to things like
     *      a UI.
     */
    struct OFTFeeDetail {
        int256 feeAmountLD; // Amount of the fee in local decimals.
        string description; // Description of the fee.
    }

    /**
     * @notice Struct representing OFT limit information.
     * @notice These amounts can change dynamically and are up to the specific oft implementation.
     */
    struct OFTLimit {
        uint256 minAmountLD; // Minimum amount in local decimals that can be sent to the recipient.
        uint256 maxAmountLD; // Maximum amount in local decimals that can be sent to the recipient.
    }

    struct OFTReceipt {
        uint256 amountSentLD; // Actual amount of tokens debited from the sender in local decimals.
        /// @notice In non-default implementations, the amountReceivedLD COULD differ from this value.
        uint256 amountReceivedLD; // Amount of tokens to be received on the remote side.
    }

    /**
     * @notice Struct representing token parameters for the OFT send() operation.
     * @param  dstEid       Destination endpoint ID.
     * @param  to           Recipient address.
     * @param  amountLD     Amount to send in local decimals.
     * @param  minAmountLD  Minimum amount to send in local decimals.
     * @param  extraOptions Additional options supplied by the caller to be used in the LayerZero
     *                      message.
     * @param  composeMsg   Composed message for the send() operation.
     * @param  oftCmd       OFT command to be executed, unused in default OFT implementations.
     */
    struct SendParam {
        uint32  dstEid;
        bytes32 to;
        uint256 amountLD;
        uint256 minAmountLD;
        bytes   extraOptions;
        bytes   composeMsg;
        bytes   oftCmd;
    }

    function quoteOFT(SendParam calldata sendParam)
        external
        view
        returns (
            OFTLimit       memory oftLimit,
            OFTFeeDetail[] memory oftFeeDetails,
            OFTReceipt     memory oftReceipt
        );

    function quoteSend(SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (MessagingFee memory msgFee);

    function send(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);

    function token() external view returns (address);

    function approvalRequired() external pure returns (bool);

}

contract LayerZeroFacet is ILayerZeroFacet, FacetBase {

    using OptionsBuilder for bytes;

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.LayerZeroFacet.v1
    struct FacetStorage {
        mapping (uint32 destinationEndpointId => bytes32 recipient) recipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.LayerZeroFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x99943b11321093c9d2d64654221621a5909374bf643d511018c800d9161d3900;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_TRANSFER = keccak256("LIMIT_LAYERZERO_TRANSFER");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _getFacetStorage().recipients[destinationEndpointId] = recipient;

        emit LayerZeroRecipientSet(destinationEndpointId, recipient);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    function transfer(address oftAddress, uint256 amount, uint32 destinationEndpointId)
        external
        payable
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressUint32Key(LIMIT_TRANSFER, oftAddress, destinationEndpointId),
            amount
        );

        bytes32 recipient = _getFacetStorage().recipients[destinationEndpointId];

        require(recipient != bytes32(0), "LayerZeroFacet/recipient-not-set");

        address proxy = $.proxy;

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before
        //       using in production.
        if (ILayerZeroLike(oftAddress).approvalRequired()) {
            ApproveLib.approve(
                ILayerZeroLike(oftAddress).token(),
                proxy,
                oftAddress,
                amount
            );
        }

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : destinationEndpointId,
            to           : recipient,
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( , , ILayerZeroLike.OFTReceipt memory receipt ) = abi.decode(
            IALMProxy(proxy).doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteOFT, (sendParams))
            ),
            (ILayerZeroLike.OFTLimit, ILayerZeroLike.OFTFeeDetail[], ILayerZeroLike.OFTReceipt)
        );

        sendParams.minAmountLD = receipt.amountReceivedLD;

        ILayerZeroLike.MessagingFee memory fee = abi.decode(
            IALMProxy(proxy).doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteSend, (sendParams, false))
            ),
            (ILayerZeroLike.MessagingFee)
        );

        IALMProxy(proxy).doCallWithValue{value: fee.nativeFee}(
            oftAddress,
            abi.encodeCall(ILayerZeroLike.send, (sendParams, fee, proxy)),
            fee.nativeFee
        );

        // Refund any excess native fee back to the caller.
        uint256 refund = msg.value - fee.nativeFee;

        if (refund > 0) {
            ( bool success, ) = msg.sender.call{value: refund}("");

            require(success, "LayerZeroFacet/refund-failed");
        }

        emit LayerZeroTransfer(oftAddress, destinationEndpointId, amount, fee.nativeFee);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getRecipient(uint32 destinationEndpointId) external view override returns (bytes32) {
        return _getFacetStorage().recipients[destinationEndpointId];
    }

}
