// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";

import "./ForkTestBase.t.sol";

contract ForeignControllerDeploySuccessTests is ForkTestBase {

    function test_deployFull() external {
        // Perform new deployments against existing fork environment

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin      : Base.SPARK_EXECUTOR,
            psm        : Base.PSM3,
            usdc       : Base.USDC,
            cctp       : Base.CCTP_TOKEN_MESSENGER
        });

        ALMProxy          newAlmProxy   = ALMProxy(payable(controllerInst.almProxy));
        ForeignController newController = ForeignController(controllerInst.controller);
        RateLimits        newRateLimits = RateLimits(controllerInst.rateLimits);

        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(newAlmProxy.hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(newRateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        _assertControllerInitState(newController, address(newAlmProxy), address(newRateLimits));
    }

    function test_deployController() external {
        // Perform new deployments against existing fork environment

        ForeignController newController = ForeignController(ForeignControllerDeploy.deployController({
            admin      : Base.SPARK_EXECUTOR,
            almProxy   : address(almProxy),
            rateLimits : address(rateLimits),
            psm        : Base.PSM3,
            usdc       : Base.USDC,
            cctp       : Base.CCTP_TOKEN_MESSENGER
        }));

        _assertControllerInitState(newController, address(almProxy), address(rateLimits));
    }

    function _assertControllerInitState(ForeignController controller, address almProxy, address rateLimits) internal view {
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, address(this)),       false);  // Deployer never gets admin

        assertEq(address(controller.proxy()),      almProxy);
        assertEq(address(controller.rateLimits()), rateLimits);
        assertEq(address(controller.psm()),        Base.PSM3);
        assertEq(address(controller.usdc()),       Base.USDC);
        assertEq(address(controller.cctp()),       Base.CCTP_TOKEN_MESSENGER);
    }

}
