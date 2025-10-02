// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ALMProxy }               from "../src/ALMProxy.sol";
import { ForeignController }      from "../src/ForeignController.sol";
import { MainnetController }      from "../src/MainnetController.sol";
import { MainnetControllerState } from "../src/MainnetControllerState.sol";
import { RateLimits }             from "../src/RateLimits.sol";

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
        address controllerState
    )
        internal returns (address controller)
    {
        controller = address(new MainnetController({
            admin_: admin,
            state_: controllerState
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

        // Deploy the state implementation
        address stateImpl = address(new MainnetControllerState());

        // Deploy TransparentUpgradeableProxy for the state
        bytes memory initData = abi.encodeWithSelector(
            MainnetControllerState.initialize.selector,
            admin,
            instance.almProxy,
            instance.rateLimits,
            vault,
            psm,
            daiUsds,
            cctp
        );

        instance.controllerState = address(new TransparentUpgradeableProxy(
            stateImpl,
            admin,
            initData
        ));

        // Deploy the main controller with the state proxy
        instance.controller = address(new MainnetController({
            admin_: admin,
            state_: instance.controllerState
        }));
    }

}
