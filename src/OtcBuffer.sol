// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AccessControlEnumerable } from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

contract OtcBuffer is AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function setAllowance(address asset, address spender, uint256 amountToAllow)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20(asset).approve(spender, amountToAllow);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
