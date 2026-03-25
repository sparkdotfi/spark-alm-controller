// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }        from "../interfaces/IALMProxy.sol";
import { IRateLimits }      from "../interfaces/IRateLimits.sol";
import { ISuperstateFacet } from "../interfaces/facets/ISuperstateFacet.sol";

import { ApproveLib } from "./ApproveLib.sol";
import { FacetBase }  from "./FacetBase.sol";

interface IUSTBLike {

    function subscribe(uint256 inAmount, address stablecoin) external;

}

// NOTE: This contract is only compatible with USTB and USDC.
contract SuperstateFacet is ISuperstateFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable usdc;
    address public immutable ustb;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address usdc_, address ustb_) {
        usdc = usdc_;
        ustb = ustb_;
    }

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function subscribe(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_SUBSCRIBE, usdcAmount);

        address proxy = $.proxy;

        ApproveLib.approve(usdc, proxy, ustb, usdcAmount);

        IALMProxy(proxy).doCall(ustb, abi.encodeCall(IUSTBLike.subscribe, (usdcAmount, usdc)));
    }

}
