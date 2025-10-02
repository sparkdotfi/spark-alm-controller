// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "../../../deploy/ControllerDeploy.sol";  // All imports needed so not importing explicitly

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract ForeignControllerDeployTests is UnitTestBase {

    function test_deployController() public {
        address admin = makeAddr("admin");
        address psm   = makeAddr("psm");
        address usdc  = makeAddr("usdc");
        address cctp  = makeAddr("cctp");

        address almProxy   = address(new ALMProxy(admin));
        address rateLimits = address(new RateLimits(admin));

        ForeignController controller = ForeignController(
            ForeignControllerDeploy.deployController(
                admin,
                almProxy,
                rateLimits,
                psm,
                usdc,
                cctp
            )
        );

        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(controller.proxy()),      almProxy);
        assertEq(address(controller.rateLimits()), rateLimits);
        assertEq(address(controller.psm()),        psm);
        assertEq(address(controller.usdc()),       usdc);
        assertEq(address(controller.cctp()),       cctp);
    }

    function test_deployFull() public {
        address admin = makeAddr("admin");
        address psm   = makeAddr("psm");
        address usdc  = makeAddr("usdc");
        address cctp  = makeAddr("cctp");

        ControllerInstance memory instance
            = ForeignControllerDeploy.deployFull(admin, psm, usdc, cctp);

        ALMProxy          almProxy   = ALMProxy(payable(instance.almProxy));
        ForeignController controller = ForeignController(instance.controller);
        RateLimits        rateLimits = RateLimits(instance.rateLimits);

        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, admin),   true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(controller.proxy()),      instance.almProxy);
        assertEq(address(controller.rateLimits()), instance.rateLimits);
        assertEq(address(controller.psm()),        psm);
        assertEq(address(controller.usdc()),       usdc);
        assertEq(address(controller.cctp()),       cctp);
    }

}

contract MainnetControllerDeployTests is UnitTestBase {

    struct TestVars {
        address daiUsds;
        address psm;
        address admin;
        address vault;
        address cctp;
    }

    function test_deployController() public {
        MainnetController controller = MainnetController(
            MainnetControllerDeploy.deployController(
                admin,
                makeAddr("state")
            )
        );

        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(controller.state()), makeAddr("state"));
    }

    function test_deployFull() public {
        TestVars memory vars;  // Avoid stack too deep

        vars.daiUsds = address(new MockDaiUsds(makeAddr("dai")));
        vars.psm     = address(new MockPSM(makeAddr("usdc")));
        vars.vault   = address(new MockVault(makeAddr("buffer")));

        vars.admin  = makeAddr("admin");
        vars.cctp   = makeAddr("cctp");

        ControllerInstance memory instance = MainnetControllerDeploy.deployFull(
            admin,
            vars.vault,
            vars.psm,
            vars.daiUsds,
            vars.cctp
        );

        ALMProxy          almProxy   = ALMProxy(payable(instance.almProxy));
        MainnetController controller = MainnetController(instance.controller);
        RateLimits        rateLimits = RateLimits(instance.rateLimits);
        MainnetControllerState state = MainnetControllerState(instance.controllerState);

        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, admin),   true);
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(state.proxy()),      instance.almProxy);
        assertEq(address(state.rateLimits()), instance.rateLimits);
        assertEq(address(state.vault()),      vars.vault);
        assertEq(address(state.buffer()),     makeAddr("buffer"));  // Buffer param in MockVault
        assertEq(address(state.psm()),        vars.psm);
        assertEq(address(state.daiUsds()),    vars.daiUsds);
        assertEq(address(state.cctp()),       vars.cctp);

        assertEq(state.psmTo18ConversionFactor(), 1e12);
    }

}
