// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }                from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { AccessControlEnumerableUpgradeable } 
    from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

contract OTCBuffer is AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    struct BufferStorage {
        address almProxy;
    }

    // keccak256(abi.encode(uint256(keccak256("otcBuffer.storage.Buffer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _BUFFER_STORAGE_LOCATION =
        0xa8ff6143ce9b2840ac86932ea3c593f97be7f3f4c76899ca3e385ef6d4c71f00;

    function _getBufferStorage() internal pure returns (BufferStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _BUFFER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor() {
        _disableInitializers();  // Avoid initializing in the context of the implementation
    }

    function initialize(address admin, address almProxy_) external initializer {
        require(admin     != address(0), "OTCBuffer/invalid-admin");
        require(almProxy_ != address(0), "OTCBuffer/invalid-alm-proxy");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        BufferStorage storage $ = _getBufferStorage();

        $.almProxy = almProxy_;
    }

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function approve(address asset, uint256 allowance)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        BufferStorage storage $ = _getBufferStorage();

        IERC20(asset).forceApprove($.almProxy, allowance);
    }

}
