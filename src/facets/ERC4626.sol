// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { IERC20 }   from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { IERC4626 } from '../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol';

import { RateLimitLib } from '../libraries/RateLimitLib.sol';
import { RolesLib }     from '../libraries/RolesLib.sol';

contract ERC4626 {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event ERC4626_AdminRoleSet(bytes32 indexed adminRole);

    event ERC4626_RelayerRoleSet(bytes32 indexed relayerRole);

    event ERC4626_MaxSlippageSet(address indexed setter, address indexed token, uint256 maxSlippage);

    event ERC4626_DepositRateLimitSet(
        address indexed setter,
        address indexed token,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event ERC4626_WithdrawRateLimitSet(
        address indexed setter,
        address indexed token,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event ERC4626_DepositRateLimitDecreased(address indexed token, uint256 amount);

    event ERC4626_WithdrawRateLimitDecreased(address indexed token, uint256 amount);

    event ERC4626_DepositRateLimitIncreased(address indexed token, uint256 amount);

    event ERC4626_Deposit(address indexed relayer, address indexed token, uint256 amount);

    event ERC4626_Withdraw(address indexed relayer, address indexed token, uint256 amount);

    event ERC4626_Redeem(address indexed relayer, address indexed token, uint256 shares);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error ERC4626_MaxSlippageNotSet(address token);

    error ERC4626_SlippageTooHigh(uint256 assets, uint256 minExpectedAssets);

    error ERC4626_DepositRateLimitExceeded(address token, uint256 amount, uint256 currentRateLimitAmount);
    error ERC4626_WithdrawRateLimitExceeded(address token, uint256 amount, uint256 currentRateLimitAmount);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.ERC4626
     * @notice The UUPS storage for the ERC4626 facet.
     */
    struct ERC4626Storage {
        bytes32 adminRole;
        bytes32 relayerRole;
        mapping(address token => uint256 maxSlippage) maxSlippages;
        mapping(address token => RateLimitLib.RateLimitData rateLimitData) depositLimits;
        mapping(address token => RateLimitLib.RateLimitData withdrawLimits) withdrawLimits;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.ERC4626')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ERC4626_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a02; // TODO: Update this.

    function _getERC4626Storage() internal pure returns (ERC4626Storage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _ERC4626_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(bytes32 adminRole_, bytes32 relayerRole_) external {
        emit ERC4626_AdminRoleSet(_getERC4626Storage().adminRole = adminRole_);
        emit ERC4626_RelayerRoleSet(_getERC4626Storage().relayerRole = relayerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(address token_, uint256 amount_) external returns (uint256 shares_) {
        _revertIfNotRelayer();
        _decreaseDepositRateLimit(token_, amount_);

        uint256 maxSlippage_ = _getERC4626Storage().maxSlippages[token_];

        if (maxSlippage_ == 0) revert ERC4626_MaxSlippageNotSet(token_);

        emit ERC4626_Deposit(msg.sender, token_, amount_);

        SafeERC20.forceApprove(IERC20(IERC4626(token_).asset()), token_, amount_);

        shares_ = IERC4626(token_).deposit(amount_, address(this));

        uint256 assets_ = IERC4626(token_).convertToAssets(shares_);
        uint256 minExpectedAssets_ = (amount_ * maxSlippage_) / 1e18;

        if (assets_ < minExpectedAssets_) revert ERC4626_SlippageTooHigh(assets_, minExpectedAssets_);
    }

    function withdraw(address token_, uint256 amount_) external returns (uint256 shares_) {
        _revertIfNotRelayer();
        _decreaseWithdrawRateLimit(token_, amount_);
        _increaseDepositRateLimit(token_, amount_);

        emit ERC4626_Withdraw(msg.sender, token_, amount_);

        return IERC4626(token_).withdraw(amount_, address(this), address(this));
    }

    function redeem(address token_, uint256 shares_) external returns (uint256 assets_) {
        _revertIfNotRelayer();

        emit ERC4626_Redeem(msg.sender, token_, shares_);

        assets_ = IERC4626(token_).redeem(shares_, address(this), address(this));

        _decreaseWithdrawRateLimit(token_, assets_);
        _increaseDepositRateLimit(token_, assets_);
    }

    function setMaxSlippage(address token_, uint256 maxSlippage_) external {
        _revertIfNotAdmin();
        emit ERC4626_MaxSlippageSet(msg.sender, token_, _getERC4626Storage().maxSlippages[token_] = maxSlippage_);
    }

    function setDepositRateLimit(
        address token_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getERC4626Storage().depositLimits[token_],
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit ERC4626_DepositRateLimitSet(msg.sender, token_, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    function setWithdrawRateLimit(
        address token_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getERC4626Storage().withdrawLimits[token_],
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit ERC4626_WithdrawRateLimitSet(msg.sender, token_, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getERC4626Storage().adminRole;
    }

    function relayerRole() external view returns (bytes32 relayerRole_) {
        return _getERC4626Storage().relayerRole;
    }

    function getMaxSlippage(address token_) external view returns (uint256 maxSlippage_) {
        return _getERC4626Storage().maxSlippages[token_];
    }

    function getDepositRateLimit(
        address token_
    ) external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getERC4626Storage().depositLimits[token_];
    }

    function getWithdrawRateLimit(
        address token_
    ) external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getERC4626Storage().withdrawLimits[token_];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseDepositRateLimit(address token_, uint256 amount_) internal {
        RateLimitLib.RateLimitData storage depositLimit_ = _getERC4626Storage().depositLimits[token_];

        emit ERC4626_DepositRateLimitDecreased(token_, amount_);

        if (RateLimitLib.decrease(depositLimit_, amount_)) return;

        revert ERC4626_DepositRateLimitExceeded(token_, amount_, RateLimitLib.getCurrentRateLimit(depositLimit_));
    }

    function _decreaseWithdrawRateLimit(address token_, uint256 amount_) internal {
        RateLimitLib.RateLimitData storage withdrawLimit_ = _getERC4626Storage().withdrawLimits[token_];

        emit ERC4626_WithdrawRateLimitDecreased(token_, amount_);

        if (RateLimitLib.decrease(withdrawLimit_, amount_)) return;

        revert ERC4626_WithdrawRateLimitExceeded(token_, amount_, RateLimitLib.getCurrentRateLimit(withdrawLimit_));
    }

    function _increaseDepositRateLimit(address token_, uint256 amount_) internal {
        emit ERC4626_DepositRateLimitIncreased(token_, amount_);

        RateLimitLib.increase(_getERC4626Storage().depositLimits[token_], amount_);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getERC4626Storage().adminRole, msg.sender);
    }

    function _revertIfNotRelayer() internal view {
        RolesLib.revertIfNotAuthorized(_getERC4626Storage().relayerRole, msg.sender);
    }

}
