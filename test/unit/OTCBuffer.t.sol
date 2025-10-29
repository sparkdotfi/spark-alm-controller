// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract OTCBufferTestBase is UnitTestBase {

    OTCBuffer public buffer;
    ERC20Mock public usdt;

    address almProxy = makeAddr("almProxy");

    function setUp() public {
        buffer = new OTCBuffer(admin, almProxy);
        usdt   = new ERC20Mock();
    }

}

contract OTCBufferConstructorTest is OTCBufferTestBase {

    function test_constructor() public {
        assertEq(buffer.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        address newAdmin = makeAddr("new-admin");

        OTCBuffer newBuffer = new OTCBuffer(newAdmin, almProxy);

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
        buffer.approve(address(usdt), 1_000_000e6);
    }

}

contract OTCBufferApproveSuccessTests is OTCBufferTestBase {

    function test_approve() public {
        assertEq(usdt.allowance(address(buffer), almProxy), 0);

        vm.prank(admin);
        buffer.approve(address(usdt), 1_000_000e6);

        assertEq(usdt.allowance(address(buffer), almProxy), 1_000_000e6);
    }

}
