// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { WEETHModule } from "src/WEETHModule.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

contract WEETHModuleTestBase is UnitTestBase {

    address almProxy = makeAddr("almProxy");

}

contract WEETHModuleInitializeTest is WEETHModuleTestBase {

    function test_initialize_invalidAdmin() public {
        address implementation = address(new WEETHModule());

        vm.expectRevert("WEETHModule/invalid-admin");
        new ERC1967Proxy(
            implementation,
            abi.encodeCall(
                WEETHModule.initialize,
                (address(0), almProxy)
            )
        );
    }

    function test_initialize_invalidAlmProxy() public {
        address implementation = address(new WEETHModule());

        vm.expectRevert("WEETHModule/invalid-alm-proxy");
        new ERC1967Proxy(
            implementation,
            abi.encodeCall(
                WEETHModule.initialize,
                (admin, address(0))
            )
        );
    }

    function test_initialize_cannotInitializeAgain() public {
        WEETHModule weethModule = WEETHModule(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new WEETHModule()),
                        abi.encodeCall(
                            WEETHModule.initialize,
                            (admin, almProxy)
                        )
                    )
                )
            )
        );

        vm.expectRevert("InvalidInitialization()");
        weethModule.initialize(admin, almProxy);
    }

    function test_initialize_cannotInitializeImplementation() public {
        WEETHModule implementation = new WEETHModule();

        vm.expectRevert("InvalidInitialization()");
        implementation.initialize(admin, almProxy);
    }

    function test_initialize_success() public {
        WEETHModule weethModule = WEETHModule(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new WEETHModule()),
                        abi.encodeCall(
                            WEETHModule.initialize,
                            (admin, almProxy)
                        )
                    )
                )
            )
        );

        assertEq(weethModule.hasRole(DEFAULT_ADMIN_ROLE, admin), true);
        assertEq(weethModule.almProxy(),                         almProxy);
    }

}
