// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface ISPKFarmLike {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
}

contract MainnetControllerSPKFarmTestBase is ForkTestBase {

    address spkFarm = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_SPK_FARM_DEPOSIT(),
                spkFarm
            ),
            10_000_000e18,
            uint256(1_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_SPK_FARM_WITHDRAW(),
                spkFarm
            ),
            10_000_000e18,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 22982805;  // July 23, 2025
    }

}

contract MainnetControllerDepositSPKFarmFailureTests is MainnetControllerSPKFarmTestBase {

    function test_depositUSDSToSPKFarm_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18);
    }

    function test_depositUSDSToSPKFarm_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositUSDSToSPKFarm(makeAddr("fake-spk-farm"), 0);
    }

    function test_depositUSDSToSPKFarm_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_SPK_FARM_DEPOSIT(),
            spkFarm
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18 + 1);

        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18);
    }

}

contract MainnetControllerSPKFarmDepositSuccessTests is MainnetControllerSPKFarmTestBase {

    function test_depositUSDSToSPKFarm() external {
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_SPK_FARM_DEPOSIT(),
            spkFarm
        );

        deal(address(usds), address(almProxy), 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                  1_000_000e18);
        assertEq(ISPKFarmLike(spkFarm).balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 9_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                  0);
        assertEq(ISPKFarmLike(spkFarm).balanceOf(address(almProxy)), 1_000_000e18);
    }

}

contract MainnetControllerSPKFarmWithdrawFailureTests is MainnetControllerSPKFarmTestBase {

    function test_withdrawUSDSFromSPKFarm_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.withdrawUSDSFromSPKFarm(spkFarm, 1_000_000e18);
    }

    function test_withdrawUSDSFromSPKFarm_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawUSDSFromSPKFarm(makeAddr("fake-spk-farm"), 0);
    }

    function test_withdrawUSDSFromSPKFarm_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_SPK_FARM_WITHDRAW(),
            spkFarm
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usds), address(almProxy), 1_000_000e18);
        vm.startPrank(relayer);
        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawUSDSFromSPKFarm(spkFarm, 1_000_000e18 + 1);

        mainnetController.withdrawUSDSFromSPKFarm(spkFarm, 1_000_000e18);
    }

}

contract MainnetControllerSPKFarmWithdrawSuccessTests is MainnetControllerSPKFarmTestBase {

    function test_withdrawUSDSFromSPKFarm() external {
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_SPK_FARM_WITHDRAW(),
            spkFarm
        );

        deal(address(usds), address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositUSDSToSPKFarm(spkFarm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                  0);
        assertEq(ISPKFarmLike(spkFarm).balanceOf(address(almProxy)), 1_000_000e18);

        skip(1 days);

        uint256 rewardTokenEarned = ISPKFarmLike(spkFarm).earned(address(almProxy));

        vm.prank(relayer);
        mainnetController.withdrawUSDSFromSPKFarm(spkFarm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                  1_000_000e18);
        assertEq(ISPKFarmLike(spkFarm).balanceOf(address(almProxy)), 0);
        assertEq(IERC20(Ethereum.SPK).balanceOf(address(almProxy)),  rewardTokenEarned);
    }

}
