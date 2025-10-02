// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ForeignController }      from "../../../src/ForeignController.sol";
import { MainnetController }      from "../../../src/MainnetController.sol";
import { MainnetControllerState } from "../../../src/MainnetControllerState.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockPSM3 }    from "../mocks/MockPSM3.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerConstructorTests is UnitTestBase {

    function test_constructor() public {
        MainnetController mainnetController = new MainnetController(
            admin,
            makeAddr("state")
        );

        assertEq(mainnetController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(mainnetController.state()),      makeAddr("state"));
    }

}

contract MainnetControllerStateInitializeTests is UnitTestBase {

    function test_constructor() public {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        // Deploy the state implementation
        address stateImpl = address(new MainnetControllerState());

        // Deploy TransparentUpgradeableProxy for the state
        bytes memory initData = abi.encodeWithSelector(
            MainnetControllerState.initialize.selector,
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(vault),
            address(psm),
            address(daiUsds),
            makeAddr("cctp")
        );

        MainnetControllerState mainnetControllerState = MainnetControllerState(address(new TransparentUpgradeableProxy(
            stateImpl,
            admin,
            initData
        )));

        assertEq(mainnetControllerState.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(mainnetControllerState.proxy()),      makeAddr("almProxy"));
        assertEq(address(mainnetControllerState.rateLimits()), makeAddr("rateLimits"));
        assertEq(address(mainnetControllerState.vault()),      address(vault));
        assertEq(address(mainnetControllerState.buffer()),     makeAddr("buffer"));  // Buffer param in MockVault
        assertEq(address(mainnetControllerState.psm()),        address(psm));
        assertEq(address(mainnetControllerState.daiUsds()),    address(daiUsds));
        assertEq(address(mainnetControllerState.cctp()),       makeAddr("cctp"));

        assertEq(mainnetControllerState.psmTo18ConversionFactor(), psm.to18ConversionFactor());
        assertEq(mainnetControllerState.psmTo18ConversionFactor(), 1e12);
    }

}

contract ForeignControllerConstructorTests is UnitTestBase {

    address almProxy   = makeAddr("almProxy");
    address rateLimits = makeAddr("rateLimits");
    address cctp       = makeAddr("cctp");
    address psm        = makeAddr("psm");
    address usdc       = makeAddr("usdc");

    function test_constructor() public {
        ForeignController foreignController = new ForeignController(
            admin,
            almProxy,
            rateLimits,
            psm,
            usdc,
            cctp
        );

        assertEq(foreignController.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(address(foreignController.proxy()),      almProxy);
        assertEq(address(foreignController.rateLimits()), rateLimits);
        assertEq(address(foreignController.psm()),        psm);
        assertEq(address(foreignController.usdc()),       usdc);   // asset1 param in MockPSM3
        assertEq(address(foreignController.cctp()),       cctp);
    }

}
