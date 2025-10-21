// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract OTCBufferTestBase is UnitTestBase {

    OTCBuffer public buffer;
    ERC20Mock public usdt;

    function setUp() public {
        buffer = new OTCBuffer(admin);
        usdt   = new ERC20Mock();
    }

}

contract OTCBufferConstructorTest is OTCBufferTestBase {

    function test_constructor() public {
        assertEq(buffer.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        address newAdmin = makeAddr("new-admin");

        OTCBuffer newBuffer = new OTCBuffer(newAdmin);

        assertEq(newBuffer.hasRole(DEFAULT_ADMIN_ROLE, newAdmin), true);
    }

}

contract OTCBufferApproveFailureTests is OTCBufferTestBase {

    function test_approve_notAuthorized() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        buffer.approve(address(usdt), address(buffer), 1_000_000e6);
    }

}

contract OTCBufferApproveSuccessTests is OTCBufferTestBase {

    function test_approve() public {
        assertEq(usdt.allowance(address(buffer), address(buffer)), 0);

        vm.prank(admin);
        buffer.approve(address(usdt), address(buffer), 1_000_000e6);

        assertEq(usdt.allowance(address(buffer), address(buffer)), 1_000_000e6);
    }

}

contract OTCBufferReceiveEthTests is OTCBufferTestBase {

    function test_receiveEth() public {
        address user = makeAddr("user");

        deal(user, 10 ether);

        assertEq(address(user).balance,   10 ether);
        assertEq(address(buffer).balance, 0);

        vm.prank(user);
        payable(address(buffer)).transfer(10 ether);

        assertEq(address(user).balance,   0);
        assertEq(address(buffer).balance, 10 ether);
    }

}
