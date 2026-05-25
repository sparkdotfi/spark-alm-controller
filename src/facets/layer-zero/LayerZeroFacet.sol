// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    OptionsBuilder
} from "../../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { ApproveLib }                         from "../../libraries/ApproveLib.sol";
import { makeAddressAddressBytes32Uint32Key } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ILayerZeroFacet } from "./ILayerZeroFacet.sol";

interface ILayerZeroLike {

    struct MessagingReceipt {
        bytes32                      guid;
        uint64                       nonce;
        ILayerZeroFacet.MessagingFee fee;
    }

    struct OFTReceipt {
        uint256 amountSentLD; // Actual amount of tokens debited from the sender in local decimals.
        /// @notice In non-default implementations, the amountReceivedLD COULD differ from this.
        uint256 amountReceivedLD; // Amount of tokens to be received on the remote side.
    }

    function decimalConversionRate() external view returns (uint256);

    function quoteSend(ILayerZeroFacet.SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (ILayerZeroFacet.MessagingFee memory msgFee);

    function send(
        ILayerZeroFacet.SendParam    calldata sendParam,
        ILayerZeroFacet.MessagingFee calldata fee,
        address                               refundAddress
    )
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);

    function token() external view returns (address);

    function approvalRequired() external pure returns (bool);

    function peers(uint32 eid) external view returns (bytes32 peer);

}

contract LayerZeroFacet is ILayerZeroFacet, Facet {

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

    bytes32 internal constant _LIMIT_TRANSFER = keccak256("LIMIT_LAYERZERO_TRANSFER");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc ILayerZeroFacet
    function setRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(recipient != bytes32(0), "LayerZeroFacet/zero-recipient");

        _getFacetStorage().recipients[destinationEndpointId] = recipient;

        emit LayerZeroRecipientSet(destinationEndpointId, recipient);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    /// @inheritdoc ILayerZeroFacet
    function transfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        payable
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        address proxy = _getSharedControllerStorage().proxy;
        address token = ILayerZeroLike(oft).token();
        bytes32 peer  = ILayerZeroLike(oft).peers(destinationEndpointId);

        (
            SendParam    memory sendParams,
            MessagingFee memory fee
        ) = quoteTransfer(oft, amount, destinationEndpointId);

        _decreaseRateLimit(
            getTransferRateLimitKey(oft, peer, destinationEndpointId, token),
            amount
        );

        // NOTE: Full integration testing of this logic is not possible without OFTs with
        //       approvalRequired == false. Add integration testing for this case before using in
        //       production.
        bool approvalRequired = ILayerZeroLike(oft).approvalRequired();

        if (approvalRequired) {
            ApproveLib.approve(token, proxy, oft, amount);
        }

        IALMProxy(proxy).doCallWithValue{value: fee.nativeFee}(
            oft,
            abi.encodeCall(ILayerZeroLike.send, (sendParams, fee, proxy)),
            fee.nativeFee
        );

        // Sweep excess ETH in controller to the proxy.
        _sweepETH();

        if (approvalRequired) {
            ApproveLib.approve(token, proxy, oft, 0);
        }

        emit LayerZeroTransfer(oft, destinationEndpointId, amount, fee.nativeFee);
    }

    /// @inheritdoc ILayerZeroFacet
    function quoteTransfer(address oft, uint256 amount, uint32 destinationEndpointId)
        public
        view
        override
        returns (SendParam memory sendParams, MessagingFee memory fee)
    {
        bytes32 recipient = _getFacetStorage().recipients[destinationEndpointId];

        require(recipient != bytes32(0), "LayerZeroFacet/recipient-not-set");

        uint256 decimalConversionRate = ILayerZeroLike(oft).decimalConversionRate();
        uint256 minAmountLD           = (amount / decimalConversionRate) * decimalConversionRate;

        require(minAmountLD > 0, "LayerZeroFacet/zero-min-amount");

        sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : recipient,
            amountLD     : amount,
            minAmountLD  : minAmountLD,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        ( bool success, bytes memory returnData ) = _getSharedControllerStorage().proxy.staticcall(
            abi.encodeCall(
                IALMProxy.doCall,
                (oft, abi.encodeCall(ILayerZeroLike.quoteSend, (sendParams, false)))
            )
        );

        require(success, "LayerZeroFacet/quoteSend-failed");

        fee = abi.decode(abi.decode(returnData, (bytes)), (MessagingFee));
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ILayerZeroFacet
    function getRecipient(uint32 destinationEndpointId) external view override returns (bytes32) {
        return _getFacetStorage().recipients[destinationEndpointId];
    }

    /// @inheritdoc ILayerZeroFacet
    function getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    )
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressBytes32Uint32Key(
            _LIMIT_TRANSFER,
            token,
            oft,
            peer,
            destinationEndpointId
        );
    }

}
