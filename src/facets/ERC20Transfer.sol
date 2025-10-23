// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { RateLimitLib } from '../libraries/RateLimitLib.sol';
import { RolesLib }     from '../libraries/RolesLib.sol';

contract ERC20Transfer {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event ERC20Transfer_AdminRoleSet(bytes32 indexed adminRole);

    event ERC20Transfer_RelayerRoleSet(bytes32 indexed relayerRole);

    event ERC20Transfer_RateLimitSet(
        address indexed setter,
        address indexed token,
        address indexed recipient,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event ERC20Transfer_Transfer(
        address indexed relayer,
        address indexed token,
        address indexed recipient,
        uint256         amount
    );

    event ERC20Transfer_RateLimitDecreased(address indexed token, address indexed recipient, uint256 amount);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error ERC20Transfer_RateLimitExceeded(address token, address recipient, uint256 amount, uint256 currentRateLimit);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.ERC20Transfer
     * @notice The UUPS storage for the ERC20Transfer facet.
     */
    struct ERC20TransferStorage {
        bytes32 adminRole;
        bytes32 relayerRole;
        mapping(address token => mapping(address recipient => RateLimitLib.RateLimitData rateLimitData)) limits;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.ERC20Transfer')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ERC20_TRANSFER_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a06; // TODO: Update this.

    function _getERC20TransferStorage() internal pure returns (ERC20TransferStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _ERC20_TRANSFER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(bytes32 adminRole_, bytes32 relayerRole_) external {
        emit ERC20Transfer_AdminRoleSet(_getERC20TransferStorage().adminRole = adminRole_);
        emit ERC20Transfer_RelayerRoleSet(_getERC20TransferStorage().relayerRole = relayerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function transfer(address token_, address recipient_, uint256 amount_) external {
        _revertIfNotRelayer();

        emit ERC20Transfer_Transfer(msg.sender, token_, recipient_, amount_);

        _decreaseRateLimit(token_, recipient_, amount_);

        SafeERC20.safeTransfer(IERC20(token_), recipient_, amount_);
    }

    function setRateLimit(
        address token_,
        address recipient_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getERC20TransferStorage().limits[token_][recipient_],
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit ERC20Transfer_RateLimitSet(msg.sender, token_, recipient_, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getERC20TransferStorage().adminRole;
    }

    function relayerRole() external view returns (bytes32 relayerRole_) {
        return _getERC20TransferStorage().relayerRole;
    }

    function getRateLimit(
        address token_,
        address recipient_
    ) external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getERC20TransferStorage().limits[token_][recipient_];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(address token_, address recipient_, uint256 amount_) internal {
        RateLimitLib.RateLimitData storage rateLimitData_ = _getERC20TransferStorage().limits[token_][recipient_];

        emit ERC20Transfer_RateLimitDecreased(token_, recipient_, amount_);

        if (RateLimitLib.decrease(rateLimitData_, amount_)) return;

        revert ERC20Transfer_RateLimitExceeded(token_, recipient_, amount_, RateLimitLib.getCurrentRateLimit(rateLimitData_));
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getERC20TransferStorage().adminRole, msg.sender);
    }

    function _revertIfNotRelayer() internal view {
        RolesLib.revertIfNotAuthorized(_getERC20TransferStorage().relayerRole, msg.sender);
    }
}
