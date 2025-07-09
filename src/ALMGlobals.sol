// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControl } from "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract ALMGlobals is AccessControl {

    address public immutable proxy;
    address public immutable rateLimits;

    constructor(address admin_, address proxy_, address rateLimits_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = proxy_;
        rateLimits = rateLimits_;
    }

}
