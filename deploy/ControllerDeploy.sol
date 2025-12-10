// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { StdCheatsSafe } from "lib/forge-std/src/StdCheats.sol";

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
        controller = StdCheatsSafe.deployCode(
            "ForeignController.sol:ForeignController",
            abi.encode(admin, almProxy, rateLimits, psm, usdc, cctp)
        );
    }

    function deployFull(
        address admin,
        address psm,
        address usdc,
        address cctp
    )
        internal returns (ControllerInstance memory instance)
    {
        instance.almProxy   = StdCheatsSafe.deployCode("ALMProxy.sol:ALMProxy",     abi.encode(admin));
        instance.rateLimits = StdCheatsSafe.deployCode("RateLimits.sol:RateLimits", abi.encode(admin));

        instance.controller = StdCheatsSafe.deployCode(
            "ForeignController.sol:ForeignController",
            abi.encode(admin, instance.almProxy, instance.rateLimits, psm, usdc, cctp)
        );
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
        controller = StdCheatsSafe.deployCode(
            "MainnetController.sol:MainnetController",
            abi.encode(admin, almProxy, rateLimits, vault, psm, daiUsds, cctp)
        );
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
        instance.almProxy   = StdCheatsSafe.deployCode("ALMProxy.sol:ALMProxy",     abi.encode(admin));
        instance.rateLimits = StdCheatsSafe.deployCode("RateLimits.sol:RateLimits", abi.encode(admin));

        instance.controller = StdCheatsSafe.deployCode(
            "MainnetController.sol:MainnetController",
            abi.encode(admin, instance.almProxy, instance.rateLimits, vault, psm, daiUsds, cctp)
        );
    }

}
