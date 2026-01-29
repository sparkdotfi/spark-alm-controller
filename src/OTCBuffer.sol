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

    struct OTCBufferStorage {
        address almProxy;
    }

    // keccak256(abi.encode(uint256(keccak256("almController.storage.OTCBuffer")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _OTC_BUFFER_STORAGE_LOCATION =
        0xe0e561841bb6fa9b0b4be53b5b4f5d506ea40664f6db7ecbcf7b6f18935a4f00;

    function _getOTCBufferStorage() internal pure returns (OTCBufferStorage storage $) {
        assembly {
            $.slot := _OTC_BUFFER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor() {
        _disableInitializers();  // Avoid initializing in the context of the implementation
    }

    function initialize(address admin, address almProxy) external initializer {
        require(admin     != address(0), "OTCBuffer/invalid-admin");
        require(almProxy  != address(0), "OTCBuffer/invalid-alm-proxy");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _getOTCBufferStorage().almProxy = almProxy;
    }

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function approve(address asset, uint256 allowance)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(asset).forceApprove(_getOTCBufferStorage().almProxy, allowance);
    }

    function almProxy() external view returns (address) {
        return _getOTCBufferStorage().almProxy;
    }

}
