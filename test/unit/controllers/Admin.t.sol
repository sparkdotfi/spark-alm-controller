// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

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

    MainnetController mainnetController;

    function setUp() public {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(vault),
            address(psm),
            address(daiUsds),
            makeAddr("cctp")
        );
    }

}

contract MainnetControllerSetMintRecipientTests is MainnetControllerAdminTestBase {

    function test_setMintRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient() public {
        assertEq(mainnetController.mintRecipients(1), bytes32(0));
        assertEq(mainnetController.mintRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(1, mintRecipient1);
        mainnetController.setMintRecipient(1, mintRecipient1);

        assertEq(mainnetController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(2, mintRecipient2);
        mainnetController.setMintRecipient(2, mintRecipient2);

        assertEq(mainnetController.mintRecipients(2), mintRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(1, mintRecipient2);
        mainnetController.setMintRecipient(1, mintRecipient2);

        assertEq(mainnetController.mintRecipients(1), mintRecipient2);
    }

}

contract MainnetControllerSetLayerZeroRecipientTests is MainnetControllerAdminTestBase {

    function test_setLayerZeroRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setLayerZeroRecipient() public {
        assertEq(mainnetController.layerZeroRecipients(1), bytes32(0));
        assertEq(mainnetController.layerZeroRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient1);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(2, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient2);
    }

}

contract MainnetControllerSetMaxSlippageTests is MainnetControllerAdminTestBase {

    function test_setMaxSlippage_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.01e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.01e18);
    }

    function test_setMaxSlippage() public {
        address pool = makeAddr("pool");

        assertEq(mainnetController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MaxSlippageSet(pool, 0.01e18);
        mainnetController.setMaxSlippage(pool, 0.01e18);

        assertEq(mainnetController.maxSlippages(pool), 0.01e18);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MaxSlippageSet(pool, 0.02e18);
        mainnetController.setMaxSlippage(pool, 0.02e18);

        assertEq(mainnetController.maxSlippages(pool), 0.02e18);
    }

}

contract ForeignControllerAdminTests is UnitTestBase {

    event LayerZeroRecipientSet(uint32 indexed destinationDomain, bytes32 layerZeroRecipient);
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

