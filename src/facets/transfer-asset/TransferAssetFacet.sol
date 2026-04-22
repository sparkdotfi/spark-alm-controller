// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ITransferAssetFacet } from "./ITransferAssetFacet.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool success);

}

contract TransferAssetFacet is ITransferAssetFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc ITransferAssetFacet
    bytes32 public constant override LIMIT_TRANSFER = keccak256("LIMIT_ASSET_TRANSFER");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc ITransferAssetFacet
    function transfer(address asset, address destination, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(LIMIT_TRANSFER, asset, destination),
            amount
        );

        bytes memory returnData = IALMProxy($.proxy).doCall(
            asset,
            abi.encodeCall(IERC20Like.transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "TransferAssetFacet/transfer-failed"
        );

        emit TransferAssetFacetTransfer(asset, destination, amount);
    }

}
