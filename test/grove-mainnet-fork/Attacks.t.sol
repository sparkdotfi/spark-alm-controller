// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

import { MainnetControllerBUIDLTestBase }  from "./Buidl.t.sol";
import { MainnetControllerEthenaE2ETests } from "./Ethena.t.sol";
import { MapleTestBase }                   from "./Maple.t.sol";

import { IMapleTokenLike } from "../../src/MainnetController.sol";

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

interface IMapleTokenExtended is IMapleTokenLike {
    function manager() external view returns (address);
}

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (address);
    function poolDelegate() external view returns (address);
}

interface IWhitelistLike {
    function addWallet(address account, string memory id) external;
    function registerInvestor(string memory id, string memory collisionHash) external;
}

contract EthenaAttackTests is MainnetControllerEthenaE2ETests {

    function test_attack_compromisedRelayer_lockingFundsInEthenaSilo() external {
        deal(address(susde), address(almProxy), 1_000_000e18);

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(1_000_000e18);

        skip(7 days);

        // Relayer is now compromised and wants to lock funds in the silo
        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(1);

        // Real relayer cannot withdraw when they want to
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        mainnetController.unstakeSUSDe();

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        skip(7 days);

        // Compromised relayer cannot perform attack anymore
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.cooldownAssetsSUSDe(1);

        // Funds have been locked in the silo this whole time
        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),              startingSiloBalance + 1_000_000e18 + 1);  // 1 wei deposit as well

        // Backstop relayer can unstake the funds
        vm.prank(backstopRelayer);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 + 1);
        assertEq(usde.balanceOf(silo),              startingSiloBalance);
    }

}

contract MapleAttackTests is MapleTestBase {

    function test_attack_compromisedRelayer_delayRequestMapleRedemption() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        // Malicious relayer delays the request for redemption for 1m
        // because new requests can't be fulfilled until the previous is fulfilled or cancelled
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), 1);

        // Cannot process request
        vm.prank(relayer);
        vm.expectRevert("WM:AS:IN_QUEUE");
        mainnetController.requestMapleRedemption(address(syrup), 500_000e6);

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        // Compromised relayer cannot perform attack anymore
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.requestMapleRedemption(address(syrup), 1);

        // Governance relayer can cancel and submit the real request
        vm.startPrank(backstopRelayer);
        mainnetController.cancelMapleRedemption(address(syrup), 1);
        mainnetController.requestMapleRedemption(address(syrup), 500_000e6);
        vm.stopPrank();
    }

}
