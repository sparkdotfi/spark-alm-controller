// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IFarmFacet }  from "../interfaces/facets/IFarmFacet.sol";

import { ApproveLib } from "./ApproveLib.sol";
import { FacetBase }  from "./FacetBase.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IFarmLike {

    function getReward() external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function stakingToken() external view returns (address);

}

contract FarmFacet is IFarmFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_DEPOSIT  = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public constant LIMIT_WITHDRAW = keccak256("LIMIT_FARM_WITHDRAW");

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function deposit(address farm, uint256 amount) external nonReentrant onlyRole(RELAYER_ROLE) {
        ControllerStorage storage $ = _getControllerStorage();

        _decreaseRateLimit($.rateLimits, LIMIT_DEPOSIT, farm, amount);

        ApproveLib.approve(IFarmLike(farm).stakingToken(), $.proxy, farm, amount);

        IALMProxy($.proxy).doCall(farm, abi.encodeCall(IFarmLike.stake, (amount)));
    }

    function withdraw(address farm, uint256 amount) external nonReentrant onlyRole(RELAYER_ROLE) {
        ControllerStorage storage $ = _getControllerStorage();

        _decreaseRateLimit($.rateLimits, LIMIT_WITHDRAW, farm, amount);

        IALMProxy($.proxy).doCall(farm, abi.encodeCall(IFarmLike.withdraw, (amount)));

        IALMProxy($.proxy).doCall(farm, abi.encodeCall(IFarmLike.getReward, ()));
    }

    /**********************************************************************************************/
    /*** Internal interactive functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address rateLimits, bytes32 key, address farm, uint256 amount)
        internal
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(makeAddressKey(key, farm), amount);
    }

}
