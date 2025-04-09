// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { MainnetController } from "../../../src/MainnetController.sol";
import { ForeignController } from "../../../src/ForeignController.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockPSM3 }    from "../mocks/MockPSM3.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerRemoveRelayerTests is UnitTestBase {

    MainnetController controller;

    address relayer1 = makeAddr("relayer1");
    address relayer2 = makeAddr("relayer2");

    event RelayerRemoved(address indexed relayer);

    function setUp() public virtual {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        controller = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(vault),
            address(psm),
            address(daiUsds),
            makeAddr("cctp")
        );

        vm.startPrank(admin);

        controller.grantRole(FREEZER, freezer);
        controller.grantRole(RELAYER, relayer1);
        controller.grantRole(RELAYER, relayer2);

        vm.stopPrank();
    }

    function test_removeRelayer_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        controller.removeRelayer(relayer);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer() public {
        assertEq(controller.hasRole(RELAYER, relayer1), true);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.prank(freezer);
        vm.expectEmit(address(controller));
        emit RelayerRemoved(relayer1);
        controller.removeRelayer(relayer1);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.prank(freezer);
        vm.expectEmit(address(controller));
        emit RelayerRemoved(relayer2);
        controller.removeRelayer(relayer2);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), false);
    }

}

contract ForeignControllerRemoveRelayerTests is UnitTestBase {

    ForeignController controller;

    address relayer1 = makeAddr("relayer1");
    address relayer2 = makeAddr("relayer2");
    address susds    = makeAddr("susds");
    address usdc     = makeAddr("usdc");
    address usds     = makeAddr("usds");

    event RelayerRemoved(address indexed relayer);

    function setUp() public {
        MockPSM3 psm3 = new MockPSM3(usds, usdc, susds);

        controller = new ForeignController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(psm3),
            usdc,
            makeAddr("cctp")
        );

        vm.startPrank(admin);

        controller.grantRole(FREEZER, freezer);
        controller.grantRole(RELAYER, relayer1);
        controller.grantRole(RELAYER, relayer2);

        vm.stopPrank();
    }

    function test_removeRelayer_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            FREEZER
        ));
        controller.removeRelayer(relayer);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin,
            FREEZER
        ));
        controller.removeRelayer(relayer);
    }

    function test_removeRelayer() public {
        assertEq(controller.hasRole(RELAYER, relayer1), true);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.prank(freezer);
        vm.expectEmit(address(controller));
        emit RelayerRemoved(relayer1);
        controller.removeRelayer(relayer1);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), true);

        vm.prank(freezer);
        vm.expectEmit(address(controller));
        emit RelayerRemoved(relayer2);
        controller.removeRelayer(relayer2);

        assertEq(controller.hasRole(RELAYER, relayer1), false);
        assertEq(controller.hasRole(RELAYER, relayer2), false);
    }

}
