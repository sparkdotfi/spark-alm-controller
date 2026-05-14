// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    ReentrancyGuardUpgradeable
} from "../../lib/oz-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import { IAccessControls } from "../interfaces/IAccessControls.sol";
import { IRateLimits }     from "../interfaces/IRateLimits.sol";

import { ControllerSharedStorage } from "../ControllerSharedStorage.sol";

import { IFacet } from "./IFacet.sol";

abstract contract Facet is IFacet, ControllerSharedStorage, ReentrancyGuardUpgradeable {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IFacet
    bytes32 public constant override DEFAULT_ADMIN_ROLE = 0x00;

    /// @inheritdoc IFacet
    bytes32 public constant override ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyRole(bytes32 role) {
        address accessControls = _getSharedControllerStorage().accessControls;

        require(
            IAccessControls(accessControls).hasRole(role, msg.sender),
            AccessControlUnauthorizedAccount(msg.sender, role)
        );

        _;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _increaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitIncrease(key, amount);
    }

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

    function _sweepETH() internal {
        _getSharedControllerStorage().proxy.call{value: address(this).balance}("");
    }

    function _tryIncreaseRateLimit(bytes32 key, uint256 amount) internal {
        if (!_rateLimitExists(key)) return;

        _increaseRateLimit(key, amount);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _rateLimitExists(bytes32 key) internal view returns (bool) {
        return IRateLimits(
            _getSharedControllerStorage().rateLimits
        ).getRateLimitData(key).maxAmount > 0;
    }

}
