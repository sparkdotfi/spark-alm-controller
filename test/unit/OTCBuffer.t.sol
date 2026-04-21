// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20Mock }    from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { IERC1967 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";

import { OTCBuffer } from "../../src/facets/otc/OTCBuffer.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

abstract contract OTCBuffer_TestBase is UnitTestBase {

    OTCBuffer internal buffer;
    ERC20Mock internal usdt;

    address internal proxy = makeAddr("proxy");

    function setUp() public {
        buffer = OTCBuffer(
            address(
                new ERC1967Proxy(
                    address(new OTCBuffer()),
                    abi.encodeCall(
                        OTCBuffer.initialize,
                        (admin, proxy)
                    )
                )
            )
        );

        usdt = new ERC20Mock();
    }

}

contract OTCBuffer_Initialize_Tests is OTCBuffer_TestBase {

    function test_initialize_invalidAdmin() external {
        address otcBuffer = address(new OTCBuffer());

        vm.expectRevert("OTCBuffer/invalid-admin");
        new ERC1967Proxy(
            otcBuffer,
            abi.encodeCall(
                OTCBuffer.initialize,
                (address(0), proxy)
            )
        );
    }

    function test_initialize_invalidAlmProxy() external {
        address otcBuffer = address(new OTCBuffer());

        vm.expectRevert("OTCBuffer/invalid-proxy");
        new ERC1967Proxy(
            otcBuffer,
            abi.encodeCall(
                OTCBuffer.initialize,
                (admin, address(0))
            )
        );
    }

    function test_initialize_cannotInitializeTwice() external {
        vm.expectRevert("InvalidInitialization()");
        buffer.initialize(admin, proxy);
    }

    function test_initialize_cannotInitializeImplementation() external {
        OTCBuffer newBuffer = new OTCBuffer();

        vm.expectRevert("InvalidInitialization()");
        newBuffer.initialize(admin, proxy);
    }

    function test_initialize() external {
        address newAdmin = makeAddr("new-admin");

        OTCBuffer newBuffer = OTCBuffer(
            address(
                new ERC1967Proxy(
                    address(new OTCBuffer()),
                    abi.encodeCall(
                        OTCBuffer.initialize,
                        (newAdmin, proxy)
                    )
                )
            )
        );

        assertEq(newBuffer.hasRole(DEFAULT_ADMIN_ROLE, newAdmin), true);
        assertEq(newBuffer.proxy(),                               proxy);
    }

}

contract OTCBuffer_Approve_Tests is OTCBuffer_TestBase {

    function test_approve_notAuthorized() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        buffer.approve(address(usdt), 1_000_000e6);
    }

    function test_approve() external {
        assertEq(usdt.allowance(address(buffer), proxy), 0);

        vm.prank(admin);
        buffer.approve(address(usdt), 1_000_000e6);

        assertEq(usdt.allowance(address(buffer), proxy), 1_000_000e6);
    }

}

contract OTCBuffer_AuthorizeUpgrade_Tests is OTCBuffer_TestBase {

    function test_authorizeUpgrade_notAuthorized() external {
        address newImplementation = address(new OTCBuffer());

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        buffer.upgradeToAndCall(newImplementation, "");
    }

    function test_authorizeUpgrade() external {
        address newImplementation = address(new OTCBuffer());

        vm.expectEmit(address(buffer));
        emit IERC1967.Upgraded(newImplementation);

        vm.prank(admin);
        buffer.upgradeToAndCall(newImplementation, "");

        // Verify the proxy still works after upgrade
        assertEq(buffer.proxy(), proxy);
    }

}
