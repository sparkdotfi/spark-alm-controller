// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { MainnetController } from "../../../src/MainnetController.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerConstructorTests is UnitTestBase {

    function test_constructor() public {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        MainnetController mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(vault),
            address(psm),
            address(daiUsds)
        );

        assertEq(mainnetController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(mainnetController.proxy()),      makeAddr("almProxy"));
        assertEq(address(mainnetController.rateLimits()), makeAddr("rateLimits"));
        assertEq(address(mainnetController.vault()),      address(vault));
        assertEq(address(mainnetController.buffer()),     makeAddr("buffer"));  // Buffer param in MockVault
        assertEq(address(mainnetController.psm()),        address(psm));
        assertEq(address(mainnetController.daiUsds()),    address(daiUsds));
        assertEq(address(mainnetController.dai()),        makeAddr("dai"));   // Dai param in MockDaiUsds
        assertEq(address(mainnetController.usdc()),       makeAddr("usdc"));  // Gem param in MockPSM

        assertEq(mainnetController.psmTo18ConversionFactor(), psm.to18ConversionFactor());
        assertEq(mainnetController.psmTo18ConversionFactor(), 1e12);
    }

}
