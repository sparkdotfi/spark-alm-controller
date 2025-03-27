// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ALMProxy }          from "../src/ALMProxy.sol";
import { MainnetController } from "../src/MainnetController.sol";
import { RateLimits }        from "../src/RateLimits.sol";

import { ControllerInstance } from "./ControllerInstance.sol";

library MainnetControllerDeploy {

    function deployController(
        address admin,
        address almProxy,
        address rateLimits,
        address vault,
        address psm,
        address daiUsds
    )
        internal returns (address controller)
    {
        controller = address(new MainnetController({
            admin_      : admin,
            proxy_      : almProxy,
            rateLimits_ : rateLimits,
            vault_      : vault,
            psm_        : psm,
            daiUsds_    : daiUsds
        }));
    }

    function deployFull(
        address admin,
        address vault,
        address psm,
        address daiUsds
    )
        internal returns (ControllerInstance memory instance)
    {
        instance.almProxy   = address(new ALMProxy(admin));
        instance.rateLimits = address(new RateLimits(admin));

        instance.controller = address(new MainnetController({
            admin_      : admin,
            proxy_      : instance.almProxy,
            rateLimits_ : instance.rateLimits,
            vault_      : vault,
            psm_        : psm,
            daiUsds_    : daiUsds
        }));
    }

}
