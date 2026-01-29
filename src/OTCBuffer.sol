// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }                from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable }          from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { AccessControlEnumerableUpgradeable } 
    from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

contract OTCBuffer is AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    using SafeERC20 for IERC20;

    address public almProxy;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address almProxy_) external initializer {
        require(admin     != address(0), "OTCBuffer/invalid-admin");
        require(almProxy_ != address(0), "OTCBuffer/invalid-alm-proxy");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        almProxy = almProxy_;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function approve(address asset, uint256 allowance)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(asset).forceApprove(almProxy, allowance);
    }

}
