// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC1967Proxy } from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20Mock }    from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract OTCBufferTestBase is UnitTestBase {

    OTCBuffer public buffer;
    ERC20Mock public usdt;

    address almProxy = makeAddr("almProxy");

    function setUp() public {
        buffer = OTCBuffer(
            address(
                new ERC1967Proxy(
                    address(new OTCBuffer()),
                    abi.encodeCall(
                        OTCBuffer.initialize,
                        (admin, almProxy)
                    )
                )
            )
        );

        usdt = new ERC20Mock();
    }

}

contract OTCBufferInitializeTests is OTCBufferTestBase {

    function test_initialize_invalidAdmin() public {
        address otcBuffer = address(new OTCBuffer());

        vm.expectRevert("OTCBuffer/invalid-admin");
        new ERC1967Proxy(
            otcBuffer,
            abi.encodeCall(
                OTCBuffer.initialize,
                (address(0), almProxy)
            )
        );
    }

    function test_initialize_invalidAlmProxy() public {
        address otcBuffer = address(new OTCBuffer());

        vm.expectRevert("OTCBuffer/invalid-alm-proxy");
        new ERC1967Proxy(
            otcBuffer,
            abi.encodeCall(
                OTCBuffer.initialize,
                (admin, address(0))
            )
        );
    }

    function test_initialize_cannotInitializeTwice() public {
        vm.expectRevert("InvalidInitialization()");
        buffer.initialize(admin, almProxy);
    }

    function test_initialize_cannotInitializeImplementation() public {
        OTCBuffer newBuffer = new OTCBuffer();

        vm.expectRevert("InvalidInitialization()");
        newBuffer.initialize(admin, almProxy);
    }

    function test_initialize() public {
        address newAdmin = makeAddr("new-admin");

        OTCBuffer newBuffer = OTCBuffer(
            address(
                new ERC1967Proxy(
                    address(new OTCBuffer()),
                    abi.encodeCall(
                        OTCBuffer.initialize,
                        (newAdmin, almProxy)
                    )
                )
            )
        );

        assertEq(newBuffer.hasRole(DEFAULT_ADMIN_ROLE, newAdmin), true);
        assertEq(newBuffer.almProxy(),                            almProxy);
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
