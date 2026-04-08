// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IFarmFacet } from "./IFarmFacet.sol";

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

    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_FARM_DEPOSIT");
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_FARM_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function deposit(address farm, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(LIMIT_DEPOSIT, farm, amount);

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(IFarmLike(farm).stakingToken(), proxy, farm, amount);

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.stake, (amount)));

        emit FarmDeposit(farm, amount);
    }

    function withdraw(address farm, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(LIMIT_WITHDRAW, farm, amount);

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.withdraw, (amount)));

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.getReward, ()));

        emit FarmWithdraw(farm, amount);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, address farm, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(key, farm),
            amount
        );
    }

}
