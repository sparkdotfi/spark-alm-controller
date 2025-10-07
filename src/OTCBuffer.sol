// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControlEnumerable }  from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }                from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract OTCBuffer is AccessControlEnumerable {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function approve(address asset, address spender, uint256 allowance)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(asset).forceApprove(spender, allowance);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
