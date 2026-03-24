// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IALMProxy }           from "../interfaces/IALMProxy.sol";
import { IRateLimits }         from "../interfaces/IRateLimits.sol";
import { ITransferAssetFacet } from "../interfaces/facets/ITransferAssetFacet.sol";

import { FacetBase } from "./FacetBase.sol";

import { makeAddressAddressKey } from "../RateLimitHelpers.sol";

contract TransferAssetFacet is ITransferAssetFacet, FacetBase {

    bytes32 public constant LIMIT_TRANSFER = keccak256("LIMIT_ASSET_TRANSFER");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function transfer(
        address asset,
        address destination,
        uint256 amount
    )
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        IRateLimits(_getControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(LIMIT_TRANSFER, asset, destination),
            amount
        );

        bytes memory returnData = IALMProxy(_getControllerStorage().proxy).doCall(
            asset,
            abi.encodeCall(IERC20.transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "TransferAssetFacet/transfer-failed"
        );
    }

}
