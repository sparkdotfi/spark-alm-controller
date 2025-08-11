// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { MainnetControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerDeploySuccessTests is ForkTestBase {

    function test_deployFull() external {
        // Perform new deployments against existing fork environment

        ControllerInstance memory controllerInst = MainnetControllerDeploy.deployFull({
            admin   : GROVE_PROXY,
            vault   : vault,
            psm     : PSM,
            daiUsds : DAI_USDS,
            cctp    : CCTP_MESSENGER
        });

        ALMProxy          newAlmProxy   = ALMProxy(payable(controllerInst.almProxy));
        MainnetController newController = MainnetController(controllerInst.controller);
        RateLimits        newRateLimits = RateLimits(controllerInst.rateLimits);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, GROVE_PROXY),   true);
        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, GROVE_PROXY),   true);
        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        _assertControllerInitState(newController, address(newAlmProxy), address(newRateLimits), vault, buffer);
    }

    function test_deployController() external {
        // Perform new deployments against existing fork environment

        MainnetController newController = MainnetController(MainnetControllerDeploy.deployController({
            admin      : GROVE_PROXY,
            almProxy   : address(almProxy),
            rateLimits : address(rateLimits),
            vault      : vault,
            psm        : PSM,
            daiUsds    : DAI_USDS,
            cctp       : CCTP_MESSENGER
        }));

        _assertControllerInitState(newController, address(almProxy), address(rateLimits), vault, buffer);
    }

    function _assertControllerInitState(MainnetController controller, address almProxy, address rateLimits, address vault, address buffer) internal view {
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, GROVE_PROXY),   true);
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);

        assertEq(address(controller.proxy()),        almProxy);
        assertEq(address(controller.rateLimits()),   rateLimits);
        assertEq(address(controller.vault()),        vault);
        assertEq(address(controller.buffer()),       buffer);
        assertEq(address(controller.psm()),          Ethereum.PSM);
        assertEq(address(controller.daiUsds()),      Ethereum.DAI_USDS);
        assertEq(address(controller.cctp()),         Ethereum.CCTP_TOKEN_MESSENGER);
        assertEq(address(controller.ethenaMinter()), Ethereum.ETHENA_MINTER);
        assertEq(address(controller.susde()),        Ethereum.SUSDE);
        assertEq(address(controller.dai()),          Ethereum.DAI);
        assertEq(address(controller.usdc()),         Ethereum.USDC);
        assertEq(address(controller.usds()),         Ethereum.USDS);
        assertEq(address(controller.usde()),         Ethereum.USDE);

        assertEq(controller.psmTo18ConversionFactor(), 1e12);
    }

}
