// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {Ethereum} from "../../lib/spark-address-registry/src/Ethereum.sol";

import {NFATFacility} from "../../lib/nfat/src/NFATFacility.sol";

import {ForkTestBase} from "./ForkTestBase.t.sol";

interface IERC721Like {
    function ownerOf(uint256 tokenId) external view returns (address);
}

// A contract with no IERC721Receiver implementation, used to test safe vs unsafe transfer behaviour.
contract NonERC721Receiver {}

abstract contract ERC721_TestBase is ForkTestBase {
    NFATFacility internal nfatFacility;

    address internal recipient = makeAddr("recipient");

    uint256 internal constant TOKEN_ID_1 = 1;
    uint256 internal constant TOKEN_ID_2 = 2;

    function setUp() public virtual override {
        super.setUp();

        nfatFacility = new NFATFacility(Ethereum.USDS, "Test NFAT", "TNFAT");
        nfatFacility.file("recipient", makeAddr("nfatRecipient"));
        nfatFacility.kiss(address(this)); // Make test contract an operator (bud)

        // Subscribe directly as almProxy and issue NFTs — bypasses the controller entirely
        // since this test is only concerned with ERC721 transfer mechanics, not NFAT logic.
        deal(Ethereum.USDS, address(almProxy), 2_000_000e18);

        vm.startPrank(address(almProxy));
        usds.approve(address(nfatFacility), 2_000_000e18);
        nfatFacility.subscribe(2_000_000e18, "");
        vm.stopPrank();

        nfatFacility.issue(address(almProxy), TOKEN_ID_1, 1_000_000e18);
        nfatFacility.issue(address(almProxy), TOKEN_ID_2, 1_000_000e18);
    }
}

contract MainnetController_ERC721_SafeTransfer_Tests is ERC721_TestBase {
    function test_safeTransferERC721_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.safeTransferERC721(address(nfatFacility), recipient, TOKEN_ID_1);
    }

    function test_safeTransferERC721_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", address(this), DEFAULT_ADMIN_ROLE
            )
        );
        mainnetController.safeTransferERC721(address(nfatFacility), recipient, TOKEN_ID_1);
    }

    function test_safeTransferERC721_nonReceiver() external {
        address nonReceiver = address(new NonERC721Receiver());

        vm.expectRevert(abi.encodeWithSignature("ERC721InvalidReceiver(address)", nonReceiver));
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.safeTransferERC721(address(nfatFacility), nonReceiver, TOKEN_ID_1);
    }

    function test_safeTransferERC721() external {
        assertEq(IERC721Like(address(nfatFacility)).ownerOf(TOKEN_ID_1), address(almProxy));

        vm.record();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.safeTransferERC721(address(nfatFacility), recipient, TOKEN_ID_1);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IERC721Like(address(nfatFacility)).ownerOf(TOKEN_ID_1), recipient);
    }
}

contract MainnetController_ERC721_Transfer_Tests is ERC721_TestBase {
    function test_transferERC721_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferERC721(address(nfatFacility), recipient, TOKEN_ID_1);
    }

    function test_transferERC721_notAdmin() external {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", address(this), DEFAULT_ADMIN_ROLE
            )
        );
        mainnetController.transferERC721(address(nfatFacility), recipient, TOKEN_ID_1);
    }

    function test_transferERC721_nonReceiver() external {
        address nonReceiver = address(new NonERC721Receiver());

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.transferERC721(address(nfatFacility), nonReceiver, TOKEN_ID_1);

        assertEq(IERC721Like(address(nfatFacility)).ownerOf(TOKEN_ID_1), nonReceiver);
    }

    function test_transferERC721() external {
        assertEq(IERC721Like(address(nfatFacility)).ownerOf(TOKEN_ID_1), address(almProxy));

        vm.record();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.transferERC721(address(nfatFacility), recipient, TOKEN_ID_1);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IERC721Like(address(nfatFacility)).ownerOf(TOKEN_ID_1), recipient);
    }
}
