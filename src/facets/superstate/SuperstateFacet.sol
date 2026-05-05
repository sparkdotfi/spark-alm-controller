// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { ISuperstateFacet } from "./ISuperstateFacet.sol";

interface IUSTBLike {

    function subscribe(uint256 inAmount, address stablecoin) external;

}

// NOTE: This contract is only compatible with USTB and USDC.
contract SuperstateFacet is ISuperstateFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_SUBSCRIBE = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ISuperstateFacet
    address public immutable override usdc;

    /// @inheritdoc ISuperstateFacet
    address public immutable override ustb;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address usdc_, address ustb_) {
        require(usdc_ != address(0), "SuperstateFacet/zero-usdc");
        require(ustb_ != address(0), "SuperstateFacet/zero-ustb");

        usdc = usdc_;
        ustb = ustb_;
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc ISuperstateFacet
    function subscribe(uint256 usdcAmount) external override nonReentrant onlyRole(ALLOCATOR_ROLE) {
        _decreaseRateLimit(subscribeRateLimitKey(), usdcAmount);

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(usdc, proxy, ustb, usdcAmount);

        IALMProxy(proxy).doCall(ustb, abi.encodeCall(IUSTBLike.subscribe, (usdcAmount, usdc)));

        emit SuperstateSubscribe(usdcAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc ISuperstateFacet
    function subscribeRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_SUBSCRIBE;
    }

}
