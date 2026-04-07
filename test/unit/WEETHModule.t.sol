// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl }           from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import { IERC1967 }                 from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";

import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IWEETHModule } from "../../src/facets/weeth/IWEETHModule.sol";

import { WEETHModule } from "../../src/facets/weeth/WEETHModule.sol";

import { UnitTestBase } from "./UnitTestBase.t.sol";

import {
    MockEETH,
    MockLiquidityPool,
    MockWEETH,
    MockWETH,
    MockWithdrawRequestNFT
} from "./mocks/MockEtherFiContracts.sol";

abstract contract WEETHModule_TestBase is UnitTestBase {

    address internal almProxy = makeAddr("almProxy");

    MockWithdrawRequestNFT internal withdrawRequestNFT;
    MockWETH               internal mockWeth;

    WEETHModule internal weethModule;

    function setUp() external {
        address implementation = address(new WEETHModule());
        weethModule = WEETHModule(payable(new ERC1967Proxy(
            implementation, abi.encodeCall(WEETHModule.initialize,(admin, almProxy))
        )));

        _mockEtherFiContracts();
    }

    function _mockEtherFiContracts() internal {
        // Deploy mock contracts and etch them at the hardcoded addresses.
        withdrawRequestNFT = new MockWithdrawRequestNFT();

        MockLiquidityPool mockLiquidityPool = new MockLiquidityPool(address(withdrawRequestNFT));
        MockEETH          mockEeth          = new MockEETH(address(mockLiquidityPool));

        vm.etch(Ethereum.WEETH, address(new MockWEETH()).code);
        MockWEETH(Ethereum.WEETH).__setEETH(address(mockEeth));

        mockWeth = new MockWETH();
        vm.etch(Ethereum.WETH, address(mockWeth).code);
        mockWeth = MockWETH(payable(Ethereum.WETH));

        // Set the request to be valid and finalized.
        withdrawRequestNFT.__setIsValid(1,     true);
        withdrawRequestNFT.__setIsFinalized(1, true);

        // Set the request to be valid but not finalized.
        withdrawRequestNFT.__setIsValid(2,     true);
        withdrawRequestNFT.__setIsFinalized(2, false);

        // Fund withdrawRequestNFT with 1 ETH to simulate the ETH received from claimWithdraw.
        deal(address(withdrawRequestNFT), 1 ether);
    }

}

contract WEETHModule_UnitTests is WEETHModule_TestBase {

    /**********************************************************************************************/
    /*** initialize Tests                                                                       ***/
    /**********************************************************************************************/

    function test_initialize_invalidAdmin() external {
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

    function test_initialize_invalidAlmProxy() external {
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

    function test_initialize_cannotInitializeAgain() external {
        vm.expectRevert("InvalidInitialization()");
        weethModule.initialize(admin, almProxy);
    }

    function test_initialize_cannotInitializeImplementation() external {
        WEETHModule implementation = new WEETHModule();

        vm.expectRevert("InvalidInitialization()");
        implementation.initialize(admin, almProxy);
    }

    function test_initialize() external {
        address implementation = address(new WEETHModule());
        WEETHModule weethModule_ = WEETHModule(payable(new ERC1967Proxy(
            implementation, abi.encodeCall(WEETHModule.initialize,(admin, almProxy))
        )));

        assertEq(weethModule_.hasRole(DEFAULT_ADMIN_ROLE, admin),     true);
        assertEq(weethModule_.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(weethModule_.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   admin);

        assertEq(weethModule_.almProxy(), almProxy);
    }

    /**********************************************************************************************/
    /*** claimWithdrawal Tests                                                                  ***/
    /**********************************************************************************************/

    function test_claimWithdrawal_invalidSender() external {
        vm.expectRevert("WEETHModule/invalid-sender");
        vm.prank(makeAddr("invalid-sender"));
        weethModule.claimWithdrawal(0);
    }

    function test_claimWithdrawal_invalidRequestId() external {
        vm.expectRevert("WEETHModule/invalid-request-id");
        vm.prank(almProxy);
        weethModule.claimWithdrawal(0);
    }

    function test_claimWithdrawal_requestNotFinalized() external {
        vm.expectRevert("WEETHModule/request-not-finalized");
        vm.prank(almProxy);
        weethModule.claimWithdrawal(2);
    }

    function test_claimWithdrawal() external {
        assertEq(address(almProxy).balance,    0);
        assertEq(mockWeth.balanceOf(almProxy), 0);
        assertEq(address(weethModule).balance, 0);

        vm.prank(almProxy);
        uint256 ethReceived = weethModule.claimWithdrawal(1);

        assertEq(address(almProxy).balance,    0);
        assertEq(ethReceived,                  1 ether);
        assertEq(mockWeth.balanceOf(almProxy), ethReceived);
        assertEq(address(weethModule).balance, 0);
    }

    /**********************************************************************************************/
    /*** onERC721Received Tests                                                                 ***/
    /**********************************************************************************************/

    function test_onERC721Received() external {
        assertEq(
            weethModule.onERC721Received(address(0), address(0), 1, ""),
            weethModule.onERC721Received.selector
        );

        assertEq(
            weethModule.onERC721Received(address(1), address(1), 1, "0xdead"),
            weethModule.onERC721Received.selector
        );
    }

    /**********************************************************************************************/
    /*** supportsInterface Tests                                                                ***/
    /**********************************************************************************************/

    function test_supportsInterface() external {
        assertEq(weethModule.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(weethModule.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(weethModule.supportsInterface(type(IERC165).interfaceId),                  true);
        assertEq(weethModule.supportsInterface(type(IWEETHModule).interfaceId),             true);
    }

    /**********************************************************************************************/
    /***  Receive function Tests                                                                ***/
    /**********************************************************************************************/

    function test_receive() external {
        deal(address(this), 1 ether);

        assertEq(address(this).balance,        1 ether);
        assertEq(address(weethModule).balance, 0);

        address(weethModule).call{value: 1 ether}("");

        assertEq(address(this).balance,        0);
        assertEq(address(weethModule).balance, 1 ether);
    }

    /**********************************************************************************************/
    /*** Upgrade function Tests                                                                 ***/
    /**********************************************************************************************/

    function test_authorizeUpgrade_notAuthorized() external {
        address newImplementation = address(new WEETHModule());

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        weethModule.upgradeToAndCall(newImplementation, "");
    }

    function test_authorizeUpgrade() external {
        address newImplementation = address(new WEETHModule());

        vm.expectEmit(address(weethModule));
        emit IERC1967.Upgraded({ implementation: newImplementation });

        vm.prank(admin);
        weethModule.upgradeToAndCall(newImplementation, "");

        // Verify the proxy still works after upgrade
        assertEq(weethModule.almProxy(), almProxy);
    }

}
