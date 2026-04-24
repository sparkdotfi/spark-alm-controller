// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IFarmFacet } from "./IFarmFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IFarmLike {

    function getReward() external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function rewardsToken() external view returns (address);

    function stakingToken() external view returns (address);

}

contract FarmFacet is IFarmFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IFarmFacet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_FARM_DEPOSIT");

    /// @inheritdoc IFarmFacet
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_FARM_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IFarmFacet
    function deposit(address farm, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(_getDepositRateLimitKey(farm), amount);

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(IFarmLike(farm).stakingToken(), proxy, farm, amount);

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.stake, (amount)));

        emit FarmDeposit(farm, amount);
    }

    /// @inheritdoc IFarmFacet
    function claimReward(address farm)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 reward)
    {
        return _claimReward(farm);
    }

    /// @inheritdoc IFarmFacet
    function withdraw(address farm, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 reward)
    {
        _decreaseRateLimit(_getWithdrawRateLimitKey(farm), amount);

        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            farm,
            abi.encodeCall(IFarmLike.withdraw, (amount))
        );

        emit FarmWithdraw(farm, amount);

        return _claimReward(farm);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _claimReward(address farm) internal returns (uint256 reward) {
        address proxy        = _getSharedControllerStorage().proxy;
        address rewardsToken = IFarmLike(farm).rewardsToken();

        uint256 startingBalance = IERC20Like(rewardsToken).balanceOf(proxy);

        IALMProxy(proxy).doCall(farm, abi.encodeCall(IFarmLike.getReward, ()));

        reward = IERC20Like(rewardsToken).balanceOf(proxy) - startingBalance;

        emit FarmReward(farm, reward);
    }

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getDepositRateLimitKey(address farm) internal view returns (bytes32) {
        return makeAddressAddressKey(LIMIT_DEPOSIT, IFarmLike(farm).stakingToken(), farm);
    }

    function _getWithdrawRateLimitKey(address farm) internal view returns (bytes32) {
        return makeAddressKey(LIMIT_WITHDRAW, farm);
    }

}
