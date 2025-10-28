// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { RateLimitLib } from '../libraries/RateLimitLib.sol';
import { RolesLib }     from '../libraries/RolesLib.sol';

interface IVaultLike {
    function buffer() external view returns (address buffer_);

    function draw(uint256 amount_) external;

    function wipe(uint256 amount_) external;
}

contract USDS {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event USDS_USDSSet(address indexed usds);

    event USDS_VaultSet(address indexed vault);

    event USDS_AdminRoleSet(bytes32 indexed adminRole);

    event USDS_RelayerRoleSet(bytes32 indexed relayerRole);

    event USDS_RateLimitSet(
        address indexed setter,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    event USDS_RateLimitDecreased(uint256 amount);

    event USDS_RateLimitIncreased(uint256 amount);

    event USDS_Mint(address indexed relayer, uint256 amount);

    event USDS_Burn(address indexed relayer, uint256 amount);

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error USDS_RateLimitExceeded(uint256 amount, uint256 currentRateLimit);

    error USDS_RateLimitZeroMaxAmount();

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.USDS
     * @notice The UUPS storage for the USDS facet.
     */
    struct USDSStorage {
        address usds;
        address vault;
        bytes32 adminRole;
        bytes32 relayerRole;
        RateLimitLib.RateLimitData rateLimitData;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.USDS')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _USDS_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a05; // TODO: Update this.

    function _getUSDSStorage() internal pure returns (USDSStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _USDS_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(address usds_, address vault_, bytes32 adminRole_, bytes32 relayerRole_) external {
        emit USDS_USDSSet(_getUSDSStorage().usds = usds_);
        emit USDS_VaultSet(_getUSDSStorage().vault = vault_);
        emit USDS_AdminRoleSet(_getUSDSStorage().adminRole = adminRole_);
        emit USDS_RelayerRoleSet(_getUSDSStorage().relayerRole = relayerRole_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function mint(uint256 amount_) external {
        _revertIfNotRelayer();
        _decreaseRateLimit(amount_);

        address vault_ = _getUSDSStorage().vault;

        emit USDS_Mint(msg.sender, amount_);

        IVaultLike(vault_).draw(amount_); // Mint USDS into the buffer

        // Transfer USDS from the buffer
        SafeERC20.safeTransferFrom(IERC20(_getUSDSStorage().usds), IVaultLike(vault_).buffer(), address(this), amount_);
    }

    function burn(uint256 amount_) external {
        _revertIfNotRelayer();
        _increaseRateLimit(amount_);

        address vault_ = _getUSDSStorage().vault;

        emit USDS_Burn(msg.sender, amount_);

        // Transfer USDS from to the buffer
        SafeERC20.safeTransfer(IERC20(_getUSDSStorage().usds), IVaultLike(vault_).buffer(), amount_);

        IVaultLike(vault_).wipe(amount_); // Burn USDS from the buffer
    }

    function setRateLimit(
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) external {
        _revertIfNotAdmin();

        RateLimitLib.set(
            _getUSDSStorage().rateLimitData,
            maxAmount_,
            slope_,
            lastAmount_,
            lastUpdated_
        );

        emit USDS_RateLimitSet(msg.sender, maxAmount_, slope_, lastAmount_, lastUpdated_);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function adminRole() external view returns (bytes32 adminRole_) {
        return _getUSDSStorage().adminRole;
    }

    function relayerRole() external view returns (bytes32 relayerRole_) {
        return _getUSDSStorage().relayerRole;
    }

    function currentRateLimit() external view returns (uint256 currentRateLimit_) {
        return RateLimitLib.getCurrentRateLimit(_getUSDSStorage().rateLimitData);
    }

    function rateLimitData() external view returns (RateLimitLib.RateLimitData memory rateLimitData_) {
        return _getUSDSStorage().rateLimitData;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(uint256 amount_) internal {
        RateLimitLib.RateLimitData storage rateLimitData_ = _getUSDSStorage().rateLimitData;

        emit USDS_RateLimitDecreased(amount_);

        if (RateLimitLib.decrease(rateLimitData_, amount_)) return;

        revert USDS_RateLimitExceeded(amount_, RateLimitLib.getCurrentRateLimit(rateLimitData_));
    }

    function _increaseRateLimit(uint256 amount_) internal {
        emit USDS_RateLimitIncreased(amount_);

        if (RateLimitLib.increase(_getUSDSStorage().rateLimitData, amount_)) return;

        revert USDS_RateLimitZeroMaxAmount();

    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        RolesLib.revertIfNotAuthorized(_getUSDSStorage().adminRole, msg.sender);
    }

    function _revertIfNotRelayer() internal view {
        RolesLib.revertIfNotAuthorized(_getUSDSStorage().relayerRole, msg.sender);
    }
}
