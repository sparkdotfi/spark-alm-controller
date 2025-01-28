// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

contract CompromisedRelayerTests is ForkTestBase {

    // Backstop relayer for this situation, larger multisig from governance
    address backstopRelayer = makeAddr("backstopRelayer");

    bytes32 key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.LIMIT_SUSDE_COOLDOWN();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.grantRole(RELAYER, backstopRelayer);
        vm.stopPrank();
    }

    function test_compromisedRelayer_lockingFundsInEthenaSilo() external {
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
