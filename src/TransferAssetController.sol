// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { ALMGlobals }       from "./ALMGlobals.sol";
import { RateLimitHelpers } from "./RateLimitHelpers.sol";

contract TransferAssetController {

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_ASSET_TRANSFER = keccak256("LIMIT_ASSET_TRANSFER");
    bytes32 public constant RELAYER              = keccak256("RELAYER");

    ALMGlobals  public immutable globals;
    IALMProxy   public immutable proxy;
    IRateLimits public immutable rateLimits;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address globals_) {
        globals    = ALMGlobals(globals_);
        proxy      = IALMProxy(globals.proxy());
        rateLimits = IRateLimits(globals.rateLimits());
    }

    /**********************************************************************************************/
    /*** Relayer ERC20 functions                                                                ***/
    /**********************************************************************************************/

    function transferAsset(address asset, address destination, uint256 amount) external {
        require(globals.hasRole(RELAYER, msg.sender), "TransferAssetController/not-relayer");

        rateLimits.triggerRateLimitDecrease(
            RateLimitHelpers.makeAssetDestinationKey(LIMIT_ASSET_TRANSFER, asset, destination),
            amount
        );

        proxy.doCall(
            asset,
            abi.encodeCall(IERC20(asset).transfer, (destination, amount))
        );
    }

}

