// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ForeignController }      from "../../../src/ForeignController.sol";
import { MainnetController }      from "../../../src/MainnetController.sol";
import { MainnetControllerState } from "../../../src/MainnetControllerState.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerAdminTestBase is UnitTestBase {

    event LayerZeroRecipientSet(uint32 indexed destinationDomain, bytes32 layerZeroRecipient);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);

    bytes32 layerZeroRecipient1 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient1"))));
    bytes32 layerZeroRecipient2 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient2"))));
    bytes32 mintRecipient1      = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 mintRecipient2      = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    MainnetController      mainnetController;
    MainnetControllerState mainnetControllerState;

    function setUp() public {
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

        mainnetControllerState = MainnetControllerState(address(new TransparentUpgradeableProxy(
            stateImpl,
            admin,
            initData
        )));

        mainnetController = new MainnetController(
            admin,
            address(mainnetControllerState)
        );
    }

}

contract MainnetControllerStateSetMintRecipientTests is MainnetControllerAdminTestBase {

    function test_setMintRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setMintRecipient(1, mintRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient() public {
        assertEq(mainnetControllerState.mintRecipients(1), bytes32(0));
        assertEq(mainnetControllerState.mintRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit MintRecipientSet(1, mintRecipient1);
        mainnetControllerState.setMintRecipient(1, mintRecipient1);

        assertEq(mainnetControllerState.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit MintRecipientSet(2, mintRecipient2);
        mainnetControllerState.setMintRecipient(2, mintRecipient2);

        assertEq(mainnetControllerState.mintRecipients(2), mintRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit MintRecipientSet(1, mintRecipient2);
        mainnetControllerState.setMintRecipient(1, mintRecipient2);

        assertEq(mainnetControllerState.mintRecipients(1), mintRecipient2);
    }

}

contract MainnetControllerStateSetLayerZeroRecipientTests is MainnetControllerAdminTestBase {

    function test_setLayerZeroRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setMintRecipient(1, mintRecipient1);
    }

    function test_setLayerZeroRecipient() public {
        assertEq(mainnetControllerState.layerZeroRecipients(1), bytes32(0));
        assertEq(mainnetControllerState.layerZeroRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit LayerZeroRecipientSet(1, layerZeroRecipient1);
        mainnetControllerState.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(mainnetControllerState.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit LayerZeroRecipientSet(2, layerZeroRecipient2);
        mainnetControllerState.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(mainnetControllerState.layerZeroRecipients(2), layerZeroRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit LayerZeroRecipientSet(1, layerZeroRecipient2);
        mainnetControllerState.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(mainnetControllerState.layerZeroRecipients(1), layerZeroRecipient2);
    }

}

contract MainnetControllerStateSetMaxSlippageTests is MainnetControllerAdminTestBase {

    function test_setMaxSlippage_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setMaxSlippage(makeAddr("pool"), 0.98e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetControllerState.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage() public {
        address pool = makeAddr("pool");

        assertEq(mainnetControllerState.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit MaxSlippageSet(pool, 0.98e18);
        mainnetControllerState.setMaxSlippage(pool, 0.98e18);

        assertEq(mainnetControllerState.maxSlippages(pool), 0.98e18);

        vm.prank(admin);
        vm.expectEmit(address(mainnetControllerState));
        emit MaxSlippageSet(pool, 0.99e18);
        mainnetControllerState.setMaxSlippage(pool, 0.99e18);

        assertEq(mainnetControllerState.maxSlippages(pool), 0.99e18);
    }

}

contract ForeignControllerAdminTests is UnitTestBase {

    event LayerZeroRecipientSet(uint32 indexed destinationDomain, bytes32 layerZeroRecipient);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);

    ForeignController foreignController;

    bytes32 layerZeroRecipient1 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient1"))));
    bytes32 layerZeroRecipient2 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient2"))));
    bytes32 mintRecipient1      = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 mintRecipient2      = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    function setUp() public {
        foreignController = new ForeignController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("cctp")
        );
    }

    function test_setMaxSlippage_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.98e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage() public {
        address pool = makeAddr("pool");

        assertEq(foreignController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MaxSlippageSet(pool, 0.98e18);
        foreignController.setMaxSlippage(pool, 0.98e18);

        assertEq(foreignController.maxSlippages(pool), 0.98e18);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MaxSlippageSet(pool, 0.99e18);
        foreignController.setMaxSlippage(pool, 0.99e18);

        assertEq(foreignController.maxSlippages(pool), 0.99e18);
    }

    function test_setMintRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMintRecipient(1, mintRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMintRecipient(1, mintRecipient1);
    }

    function test_setLayerZeroRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

    function test_setMintRecipient() public {
        assertEq(foreignController.mintRecipients(1), bytes32(0));
        assertEq(foreignController.mintRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(1, mintRecipient1);
        foreignController.setMintRecipient(1, mintRecipient1);

        assertEq(foreignController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(2, mintRecipient2);
        foreignController.setMintRecipient(2, mintRecipient2);

        assertEq(foreignController.mintRecipients(2), mintRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(1, mintRecipient2);
        foreignController.setMintRecipient(1, mintRecipient2);

        assertEq(foreignController.mintRecipients(1), mintRecipient2);
    }

    function test_setLayerZeroRecipient() public {
        assertEq(foreignController.layerZeroRecipients(1), bytes32(0));
        assertEq(foreignController.layerZeroRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient1);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(2, layerZeroRecipient2);
        foreignController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient2);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient2);
    }

}

