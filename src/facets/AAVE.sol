// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { RateLimitLib } from '../libraries/RateLimitLib.sol';
import { RolesLib }     from '../libraries/RolesLib.sol';

interface IATokenLike {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function POOL() external view returns (address);
}

interface IPoolLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address recipient) external returns (uint256 withdrawn);
}

contract AAVE {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event AAVE_AdminRoleSet(bytes32 indexed adminRole);

    event AAVE_RelayerRoleSet(bytes32 indexed relayerRole);

    event AAVE_MaxSlippageSet(address indexed setter, address indexed aToken, uint256 maxSlippage);

    event AAVE_DepositRateLimitSet(
        address indexed setter,
        address indexed aToken,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event AAVE_WithdrawRateLimitSet(
        address indexed setter,
        address indexed aToken,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event AAVE_DepositRateLimitDecreased(address indexed aToken, uint256 amount);

    event AAVE_WithdrawRateLimitDecreased(address indexed aToken, uint256 amount);

    event AAVE_DepositRateLimitIncreased(address indexed aToken, uint256 amount);

    event AAVE_Deposit(address indexed relayer, address indexed aToken, uint256 amount);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error AAVE_MaxSlippageNotSet(address aToken);

    error AAVE_SlippageTooHigh(uint256 amount, uint256 minExpectedAmount);

    error AAVE_DepositRateLimitExceeded(address aToken, uint256 amount, uint256 currentRateLimitAmount);

    error AAVE_DepositRateLimitZeroMaxAmount();

    error AAVE_WithdrawRateLimitExceeded(address aToken, uint256 amount, uint256 currentRateLimitAmount);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.AAVE
     * @notice The UUPS storage for the AAVE facet.
     */
    struct AAVEStorage {
        bytes32 adminRole;
        bytes32 relayerRole;
        mapping(address aToken => uint256 maxSlippage) maxSlippages;
        mapping(address aToken => RateLimitLib.RateLimitData rateLimitData) depositLimits;
        mapping(address aToken => RateLimitLib.RateLimitData withdrawLimits) withdrawLimits;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.AAVE')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _AAVE_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a08; // TODO: Update this.

    function _getAAVEStorage() internal pure returns (AAVEStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _AAVE_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(bytes32 adminRole_, bytes32 relayerRole_) external {
        emit AAVE_AdminRoleSet(_getAAVEStorage().adminRole = adminRole_);
        emit AAVE_RelayerRoleSet(_getAAVEStorage().relayerRole = relayerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(address aToken_, uint256 amount_) external {
        _revertIfNotRelayer();
        _decreaseDepositRateLimit(aToken_, amount_);

        uint256 maxSlippage_ = _getAAVEStorage().maxSlippages[aToken_];

        if (maxSlippage_ == 0) revert AAVE_MaxSlippageNotSet(aToken_);

        emit AAVE_Deposit(msg.sender, aToken_, amount_);

        address underlying_ = IATokenLike(aToken_).UNDERLYING_ASSET_ADDRESS();
        address pool_       = IATokenLike(aToken_).POOL();

        SafeERC20.forceApprove(IERC20(underlying_), pool_, amount_);

        uint256 aTokenBalance_ = IERC20(aToken_).balanceOf(address(this));

        // Deposit underlying into Aave pool, receiving aTokens
        IPoolLike(pool_).supply(underlying_, amount_, address(this), 0);

        uint256 receivedATokens_    = IERC20(aToken_).balanceOf(address(this)) - aTokenBalance_;
        uint256 minExpectedATokens_ = (amount_ * maxSlippage_) / 1e18;

        if (receivedATokens_ < minExpectedATokens_) revert AAVE_SlippageTooHigh(receivedATokens_, minExpectedATokens_);
    }

    function withdraw(address aToken_, uint256 amount_) external returns (uint256 amountWithdrawn_) {
        _revertIfNotRelayer();

        address pool_       = IATokenLike(aToken_).POOL();
        address underlying_ = IATokenLike(aToken_).UNDERLYING_ASSET_ADDRESS();

        amountWithdrawn_ = IPoolLike(pool_).withdraw(underlying_, amount_, address(this));

        _decreaseWithdrawRateLimit(aToken_, amountWithdrawn_);
        _increaseDepositRateLimit(aToken_, amountWithdrawn_);
    }

    function setMaxSlippage(address aToken_, uint256 maxSlippage_) external {
        _revertIfNotAdmin();
        emit AAVE_MaxSlippageSet(msg.sender, aToken_, _getAAVEStorage().maxSlippages[aToken_] = maxSlippage_);
    }

    function setDepositRateLimit(
        address aToken_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getAAVEStorage().depositLimits[aToken_],
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit AAVE_DepositRateLimitSet(msg.sender, aToken_, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    function setWithdrawRateLimit(
        address aToken_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getAAVEStorage().withdrawLimits[aToken_],
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit AAVE_WithdrawRateLimitSet(msg.sender, aToken_, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getAAVEStorage().adminRole;
    }

    function relayerRole() external view returns (bytes32 relayerRole_) {
        return _getAAVEStorage().relayerRole;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseDepositRateLimit(address aToken_, uint256 amount_) internal {
        RateLimitLib.RateLimitData storage depositLimit_ = _getAAVEStorage().depositLimits[aToken_];

        emit AAVE_DepositRateLimitDecreased(aToken_, amount_);

        if (RateLimitLib.decrease(depositLimit_, amount_)) return;

        revert AAVE_DepositRateLimitExceeded(aToken_, amount_, RateLimitLib.getCurrentRateLimit(depositLimit_));
    }

    function _decreaseWithdrawRateLimit(address aToken_, uint256 amount_) internal {
        RateLimitLib.RateLimitData storage withdrawLimit_ = _getAAVEStorage().withdrawLimits[aToken_];

        emit AAVE_WithdrawRateLimitDecreased(aToken_, amount_);

        if (RateLimitLib.decrease(withdrawLimit_, amount_)) return;

        revert AAVE_WithdrawRateLimitExceeded(aToken_, amount_, RateLimitLib.getCurrentRateLimit(withdrawLimit_));
    }

    function _increaseDepositRateLimit(address aToken_, uint256 amount_) internal {
        emit AAVE_DepositRateLimitIncreased(aToken_, amount_);

        if (RateLimitLib.increase(_getAAVEStorage().depositLimits[aToken_], amount_)) return;

        revert AAVE_DepositRateLimitZeroMaxAmount();
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getAAVEStorage().adminRole, msg.sender);
    }

    function _revertIfNotRelayer() internal view {
        RolesLib.revertIfNotAuthorized(_getAAVEStorage().relayerRole, msg.sender);
    }

}
