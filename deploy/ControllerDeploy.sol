// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ALMProxy }          from "../src/ALMProxy.sol";
import { ForeignController } from "../src/ForeignController.sol";
import { MainnetController } from "../src/MainnetController.sol";
import { RateLimits }        from "../src/RateLimits.sol";

import { ControllerInstance } from "./ControllerInstance.sol";

library ForeignControllerDeploy {

    function deployController(
        address admin,
        address almProxy,
        address rateLimits,
        address psm,
        address usdc,
        address cctp
    )
        internal returns (address controller)
    {
        controller = address(new ForeignController({
            admin_      : admin,
            proxy_      : almProxy,
            rateLimits_ : rateLimits,
            psm_        : psm,
            usdc_       : usdc,
            cctp_       : cctp
        }));
    }

    function deployFull(
        address admin,
        address psm,
        address usdc,
        address cctp
    )
        internal returns (ControllerInstance memory instance)
    {
        instance.almProxy   = address(new ALMProxy(admin));
        instance.rateLimits = address(new RateLimits(admin));

        instance.controller = address(new ForeignController({
            admin_      : admin,
            proxy_      : instance.almProxy,
            rateLimits_ : instance.rateLimits,
            psm_        : psm,
            usdc_       : usdc,
            cctp_       : cctp
        }));
    }

}

library MainnetControllerDeploy {

    function deployController(
        address admin,
        address almProxy,
        address rateLimits,
        address vault,
        address psm,
        address daiUsds,
        address cctp
    )
        internal returns (address controller)
    {
        controller = address(new MainnetController({
            admin_      : admin,
            proxy_      : almProxy,
            rateLimits_ : rateLimits,
            vault_      : vault,
            psm_        : psm,
            daiUsds_    : daiUsds,
            cctp_       : cctp
        }));
    }

    function deployFull(
        address admin,
        address vault,
        address psm,
        address daiUsds,
        address cctp
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
            daiUsds_    : daiUsds,
            cctp_       : cctp
        }));
    }

}
