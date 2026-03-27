// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    OptionsBuilder
} from "../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import {
    ILayerZeroLike,
    SendParam,
    OFTReceipt,
    MessagingFee,
    OFTLimit,
    OFTFeeDetail
} from "../interfaces/ILayerZero.sol";

import { IRateLimits }     from "../interfaces/IRateLimits.sol";
import { IALMProxy }       from "../interfaces/IALMProxy.sol";
import { ILayerZeroFacet } from "../interfaces/facets/ILayerZeroFacet.sol";

import { makeAddressUint32Key } from "../RateLimitHelpers.sol";

import { ApproveLib } from "./ApproveLib.sol";
import { FacetBase }  from "./FacetBase.sol";

contract LayerZeroFacet is ILayerZeroFacet, FacetBase {

    using OptionsBuilder for bytes;

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.LayerZeroFacet
    struct FacetStorage {
        mapping(uint32 destinationEndpointId => bytes32 recipient) recipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.LayerZeroFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x35cbf4f8cec8cb8b455a904d7cdf14cb711e472d3d2849a8f6b768a7e6d72800;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_LAYERZERO_TRANSFER");

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
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

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : recipient,
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        // Query the min amount received on the destination chain and set it.
        ( , , OFTReceipt memory receipt ) = abi.decode(
            IALMProxy(proxy).doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteOFT, (sendParams))
            ),
            (OFTLimit, OFTFeeDetail[], OFTReceipt)
        );

        sendParams.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = abi.decode(
            IALMProxy(proxy).doCall(
                oftAddress,
                abi.encodeCall(ILayerZeroLike.quoteSend, (sendParams, false))
            ),
            (MessagingFee)
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
    }

    /**********************************************************************************************/
    /*** External View/Pure functions                                                           ***/
    /**********************************************************************************************/

    function getRecipient(uint32 destinationEndpointId) external view returns (bytes32) {
        return _getFacetStorage().recipients[destinationEndpointId];
    }

}
