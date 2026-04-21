// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IERC20Metadata as IERC20
} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {
    SafeERC20
} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    AccessControlEnumerableUpgradeable
} from "../../../lib/oz-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {
    UUPSUpgradeable
} from "../../../lib/oz-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IOTCBuffer } from "./IOTCBuffer.sol";

contract OTCBuffer is IOTCBuffer, AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.OTCBuffer.v1
    struct OTCBufferStorage {
        address proxy;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.OTCBuffer.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _OTC_BUFFER_STORAGE_LOCATION =
        0xdf8a96fe84cc14b4811a66999a35db8d1aac360166b1b48140c2e05816220300;

    function _getOTCBufferStorage() internal pure returns (OTCBufferStorage storage $) {
        assembly {
            $.slot := _OTC_BUFFER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor() {
        _disableInitializers();  // Avoid initializing in the context of the implementation
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(address admin_, address proxy_) external override initializer {
        require(admin_ != address(0), "OTCBuffer/invalid-admin");
        require(proxy_ != address(0), "OTCBuffer/invalid-proxy");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _getOTCBufferStorage().proxy = proxy_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function approve(address asset, uint256 allowance)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(asset).forceApprove(_getOTCBufferStorage().proxy, allowance);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function proxy() external view override returns (address) {
        return _getOTCBufferStorage().proxy;
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IOTCBuffer, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IOTCBuffer).interfaceId || super.supportsInterface(interfaceId);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

}
