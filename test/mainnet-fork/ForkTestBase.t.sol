// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { DssTest } from "../../lib/dss-test/src/DssTest.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { Domain, DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { ALMProxy } from "../../src/ALMProxy.sol";

import { Roles } from "../../src/facets/Roles.sol";

contract ForkTestBase is DssTest {

    using DomainHelpers for *;

    address freezer = Ethereum.ALM_FREEZER;
    address relayer = Ethereum.ALM_RELAYER;

    bytes32 constant ADMIN_ROLE   = "ADMIN";
    bytes32 constant FREEZER_ROLE = "FREEZER";
    bytes32 constant RELAYER_ROLE = "RELAYER";

    address payable almProxy;

    address rolesFacet;

    Domain source;

    function setUp() public virtual {
        source = getChain("mainnet").createSelectFork(_getBlock());

        almProxy = payable(new ALMProxy(Ethereum.SPARK_PROXY));

        rolesFacet = address(new Roles());

        bytes4[] memory functionSelectors = new bytes4[](4);
        functionSelectors[0] = Roles.grantRole.selector;
        functionSelectors[1] = Roles.revokeRole.selector;
        functionSelectors[2] = Roles.adminRole.selector;
        functionSelectors[3] = Roles.hasRole.selector;

        ALMProxy.Implementation[] memory implementations = new ALMProxy.Implementation[](4);
        implementations[0] = ALMProxy.Implementation({
            implementation: rolesFacet,
            functionSelector: Roles.grantRole.selector
        });
        implementations[1] = ALMProxy.Implementation({
            implementation: rolesFacet,
            functionSelector: Roles.revokeRole.selector
        });
        implementations[2] = ALMProxy.Implementation({
            implementation: rolesFacet,
            functionSelector: Roles.adminRole.selector
        });
        implementations[3] = ALMProxy.Implementation({
            implementation: rolesFacet,
            functionSelector: Roles.hasRole.selector
        });

        vm.startPrank(Ethereum.SPARK_PROXY);
        ALMProxy(almProxy).setImplementations(functionSelectors, implementations);
        ALMProxy(almProxy).delegateCall(rolesFacet, abi.encodeCall(Roles.initialize, (Ethereum.SPARK_PROXY)));
        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 20917850; //  October 7, 2024
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function test_selectors() external {
        assertEq(ALMProxy(almProxy).admin(), Ethereum.SPARK_PROXY);
        assertEq(Roles(almProxy).adminRole(), ADMIN_ROLE);
        assertEq(Roles(almProxy).hasRole(Roles(almProxy).adminRole(), Ethereum.SPARK_PROXY), true);
    }

    function test_grantAndRevokeRole() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        Roles(almProxy).grantRole(ADMIN_ROLE, makeAddr("alice"));
        vm.stopPrank();

        assertTrue(Roles(almProxy).hasRole(ADMIN_ROLE, makeAddr("alice")));

        vm.startPrank(Ethereum.SPARK_PROXY);
        Roles(almProxy).revokeRole(ADMIN_ROLE, makeAddr("alice"));
        vm.stopPrank();

        assertFalse(Roles(almProxy).hasRole(ADMIN_ROLE, makeAddr("alice")));
    }
}
