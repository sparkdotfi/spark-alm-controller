// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { MainnetController_Ethena_E2ETests } from "./Ethena.t.sol";
import { Maple_TestBase }                    from "./Maple.t.sol";

contract MainnetController_Ethena_Attack_Tests is MainnetController_Ethena_E2ETests {

    function test_attack_compromisedAllocator_lockingFundsInEthenaSilo() external {
        deal(address(susde), address(almProxy), 1_000_000e18);

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        vm.prank(allocator);
        mainnetController.ethena_cooldownAssets(1_000_000e18);

        skip(7 days);

        // Allocator is now compromised and wants to lock funds in the silo
        vm.prank(allocator);
        mainnetController.ethena_cooldownAssets(1);

        // Real allocator cannot withdraw when they want to
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        vm.prank(allocator);
        mainnetController.ethena_unstake();

        // Allocator admin can remove the compromised allocator and fallback to the governance allocator
        vm.prank(allocatorAdmin);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);

        skip(7 days);

        // Compromised allocator cannot perform attack anymore
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            allocator,
            ALLOCATOR_ROLE
        ));
        vm.prank(allocator);
        mainnetController.ethena_cooldownAssets(1);

        // Funds have been locked in the silo this whole time
        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),              startingSiloBalance + 1_000_000e18 + 1);  // 1 wei deposit as well

        // Backstop allocator can unstake the funds
        vm.prank(backstopAllocator);
        mainnetController.ethena_unstake();

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 + 1);
        assertEq(usde.balanceOf(silo),              startingSiloBalance);
    }

}

contract MainnetController_Maple_Attack_Tests is Maple_TestBase {

    function test_attack_compromisedAllocator_delayRequestMapleRedemption() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(allocator);
        mainnetController.erc4626_deposit(address(SYRUP), 1_000_000e6, 0);

        // Malicious allocator delays the request for redemption for 1m
        // because new requests can't be fulfilled until the previous is fulfilled or cancelled
        vm.prank(allocator);
        mainnetController.maple_requestRedemption(address(SYRUP), 1);

        // Cannot process request
        vm.prank(allocator);
        vm.expectRevert("WM:AS:IN_QUEUE");
        mainnetController.maple_requestRedemption(address(SYRUP), 500_000e6);

        // Allocator admin can remove the compromised allocator and fallback to the governance allocator
        vm.prank(allocatorAdmin);
        accessControls.revokeRole(ALLOCATOR_ROLE, allocator);

        // Compromised allocator cannot perform attack anymore
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            allocator,
            ALLOCATOR_ROLE
        ));
        mainnetController.maple_requestRedemption(address(SYRUP), 1);

        // Governance allocator can cancel and submit the real request
        vm.startPrank(backstopAllocator);
        mainnetController.maple_cancelRedemption(address(SYRUP), 1);
        mainnetController.maple_requestRedemption(address(SYRUP), 500_000e6);
        vm.stopPrank();
    }

}
