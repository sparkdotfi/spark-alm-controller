// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Address }   from '../../lib/openzeppelin-contracts/contracts/utils/Address.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { RateLimitLib } from '../libraries/RateLimitLib.sol';
import { RolesLib }     from '../libraries/RolesLib.sol';

interface IWETHLike {
    function withdraw(uint256 amount) external;
}

interface IWstETHLike {
    function getStETHByWstETH(uint256 amount) external view returns (uint256 stETHAmount);
}

interface IWithdrawalQueueLike {
    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner)
        external returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 requestId) external;
}

contract WSTETH {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event WSTETH_WETHSet(address indexed weth);

    event WSTETH_WSTETHSet(address indexed wsteth);

    event WSTETH_WSTETHWithdrawQueueSet(address indexed wstethWithdrawQueue);

    event WSTETH_AdminRoleSet(bytes32 indexed adminRole);

    event WSTETH_RelayerRoleSet(bytes32 indexed relayerRole);

    event WSTETH_DepositRateLimitSet(
        address indexed setter,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event WSTETH_RequestWithdrawRateLimitSet(
        address indexed setter,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event WSTETH_DepositRateLimitDecreased(uint256 amount);

    event WSTETH_RequestWithdrawRateLimitDecreased(uint256 amount);

    event WSTETH_Deposit(address indexed relayer, uint256 amount);

    event WSTETH_WithdrawalRequested(address indexed relayer, uint256 amount, uint256[] requestIds);

    event WSTETH_WithdrawalClaimed(address indexed relayer, uint256 indexed requestId, uint256 amount);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error WSTETH_DepositRateLimitExceeded(uint256 amount, uint256 currentRateLimit);

    error WSTETH_RequestWithdrawRateLimitExceeded(uint256 amount, uint256 currentRateLimit);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.WSTETH
     * @notice The UUPS storage for the WSTETH facet.
     */
    struct WSTETHStorage {
        address weth;
        address wsteth;
        address wstethWithdrawQueue;
        bytes32 adminRole;
        bytes32 relayerRole;
        RateLimitLib.RateLimitData depositRateLimitData;
        RateLimitLib.RateLimitData requestWithdrawRateLimitData;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.WSTETH')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _WSTETH_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a06; // TODO: Update this.

    function _getWSTETHStorage() internal pure returns (WSTETHStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _WSTETH_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(
        address weth_,
        address wsteth_,
        address wstethWithdrawQueue_,
        bytes32 adminRole_,
        bytes32 relayerRole_
    ) external {
        emit WSTETH_WETHSet(_getWSTETHStorage().weth = weth_);
        emit WSTETH_WSTETHSet(_getWSTETHStorage().wsteth = wsteth_);
        emit WSTETH_WSTETHWithdrawQueueSet(_getWSTETHStorage().wstethWithdrawQueue = wstethWithdrawQueue_);
        emit WSTETH_AdminRoleSet(_getWSTETHStorage().adminRole = adminRole_);
        emit WSTETH_RelayerRoleSet(_getWSTETHStorage().relayerRole = relayerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(uint256 amount) external {
        _revertIfNotRelayer();
        _decreaseDepositRateLimit(amount);

        emit WSTETH_Deposit(msg.sender, amount);

        IWETHLike(_getWSTETHStorage().weth).withdraw(amount);

        Address.sendValue(payable(_getWSTETHStorage().wsteth), amount);
    }

    function requestWithdraw(uint256 amount_) external returns (uint256[] memory requestIds_) {
        _revertIfNotRelayer();

        address wsteth_ = _getWSTETHStorage().wsteth;

        _decreaseRequestWithdrawRateLimit(IWstETHLike(wsteth_).getStETHByWstETH(amount_));

        address wstethWithdrawQueue_ = _getWSTETHStorage().wstethWithdrawQueue;

        SafeERC20.forceApprove(IERC20(wsteth_), wstethWithdrawQueue_, amount_);

        uint256[] memory amountsToRedeem_ = new uint256[](1);
        amountsToRedeem_[0] = amount_;

        (
            requestIds_
        ) = IWithdrawalQueueLike(wstethWithdrawQueue_).requestWithdrawalsWstETH(amountsToRedeem_, address(this));

        emit WSTETH_WithdrawalRequested(msg.sender, amount_, requestIds_);
    }

    function claimWithdrawal(uint256 requestId_) external {
        _revertIfNotRelayer();

        uint256 initialEthBalance_ = address(this).balance;

        IWithdrawalQueueLike(_getWSTETHStorage().wstethWithdrawQueue).claimWithdrawal(requestId_);

        uint256 ethReceived_ = address(this).balance - initialEthBalance_;

        Address.sendValue(payable(_getWSTETHStorage().weth), ethReceived_);

        emit WSTETH_WithdrawalClaimed(msg.sender, requestId_, ethReceived_);
    }

    function setDepositRateLimit(
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getWSTETHStorage().depositRateLimitData,
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit WSTETH_DepositRateLimitSet(msg.sender, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    function setRequestWithdrawRateLimit(
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getWSTETHStorage().requestWithdrawRateLimitData,
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit WSTETH_RequestWithdrawRateLimitSet(msg.sender, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getWSTETHStorage().adminRole;
    }

    function relayerRole() external view returns (bytes32 relayerRole_) {
        return _getWSTETHStorage().relayerRole;
    }

    function depositRateLimit() external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getWSTETHStorage().depositRateLimitData;
    }

    function requestWithdrawRateLimit() external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getWSTETHStorage().requestWithdrawRateLimitData;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseDepositRateLimit(uint256 amount_) internal {
        RateLimitLib.RateLimitData storage rateLimitData_ = _getWSTETHStorage().depositRateLimitData;

        emit WSTETH_DepositRateLimitDecreased(amount_);

        if (RateLimitLib.decrease(rateLimitData_, amount_)) return;

        revert WSTETH_DepositRateLimitExceeded(amount_, RateLimitLib.getCurrentRateLimit(rateLimitData_));
    }

    function _decreaseRequestWithdrawRateLimit(uint256 amount_) internal {
        RateLimitLib.RateLimitData storage rateLimitData_ = _getWSTETHStorage().requestWithdrawRateLimitData;

        emit WSTETH_RequestWithdrawRateLimitDecreased(amount_);

        if (RateLimitLib.decrease(rateLimitData_, amount_)) return;

        revert WSTETH_RequestWithdrawRateLimitExceeded(amount_, RateLimitLib.getCurrentRateLimit(rateLimitData_));
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getWSTETHStorage().adminRole, msg.sender);
    }

    function _revertIfNotRelayer() internal view {
        RolesLib.revertIfNotAuthorized(_getWSTETHStorage().relayerRole, msg.sender);
    }

}
