// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { Controller } from "./Controller.sol";

contract ForeignController is Controller, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    IALMProxy   public immutable proxy;
    IRateLimits public immutable rateLimits;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin_, address proxy_, address rateLimits_, address accessControls_)
        Controller(accessControls_, proxy_, rateLimits_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = IALMProxy(proxy_);
        rateLimits = IRateLimits(rateLimits_);
    }

}
