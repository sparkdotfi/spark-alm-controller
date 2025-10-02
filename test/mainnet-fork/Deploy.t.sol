// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { MainnetControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerDeploySuccessTests is ForkTestBase {

    function test_deployFull() external {
        // Perform new deployments against existing fork environment

        ControllerInstance memory controllerInst = MainnetControllerDeploy.deployFull({
            admin   : SPARK_PROXY,
            vault   : vault,
            psm     : PSM,
            daiUsds : DAI_USDS,
            cctp    : CCTP_MESSENGER
        });

        ALMProxy          newAlmProxy             = ALMProxy(payable(controllerInst.almProxy));
        MainnetController newController           = MainnetController(controllerInst.controller);
        RateLimits        newRateLimits           = RateLimits(controllerInst.rateLimits);
        MainnetControllerState newControllerState = MainnetControllerState(controllerInst.controllerState);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY),   true);
        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY),   true);
        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        assertEq(newControllerState.hasRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY),   true);
        assertEq(newControllerState.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);  // Deployer never gets admin

        _assertControllerInitState(newController, controllerInst.controllerState);

        assertEq(address(newControllerState.proxy()),      address(newAlmProxy));
        assertEq(address(newControllerState.rateLimits()), address(newRateLimits));
        assertEq(address(newControllerState.vault()),      vault);
        assertEq(address(newControllerState.buffer()),     buffer);
        assertEq(address(newControllerState.psm()),        PSM);
        assertEq(address(newControllerState.daiUsds()),    DAI_USDS);
        assertEq(address(newControllerState.cctp()),       CCTP_MESSENGER);
    }

    function test_deployController() external {
        // Perform new deployments against existing fork environment

        MainnetController newController = MainnetController(MainnetControllerDeploy.deployController({
            admin           : SPARK_PROXY,
            controllerState : address(mainnetControllerState)
        }));

        _assertControllerInitState(newController, address(mainnetControllerState));
    }

    function _assertControllerInitState(MainnetController controller, address state) internal view {
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, SPARK_PROXY),   true);
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, address(this)), false);

        assertEq(address(controller.state()), state);
    }

}
