// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IFarmLike {
    function balanceOf(address account) external view returns (uint256);
}

contract MainnetControllerFarmTestBase is ForkTestBase {

    address farm = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;  // USDS SPK farm

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_FARM_DEPOSIT(),
                farm
            ),
            10_000_000e18,
            uint256(1_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_FARM_WITHDRAW(),
                farm
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

contract MainnetControllerDepositFarmFailureTests is MainnetControllerFarmTestBase {

    function test_depositToFarm_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositToFarm(farm, 1_000_000e18);
    }

    function test_depositToFarm_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositToFarm(makeAddr("fake-farm"), 0);
    }

    function test_depositToFarm_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_FARM_DEPOSIT(),
            farm
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usds), address(almProxy), 1_000_000e18);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositToFarm(farm, 1_000_000e18 + 1);

        mainnetController.depositToFarm(farm, 1_000_000e18);
    }

}

contract MainnetControllerFarmDepositSuccessTests is MainnetControllerFarmTestBase {

    function test_depositToFarm() external {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_FARM_DEPOSIT(),
            farm
        );

        deal(address(usds), address(almProxy), 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),            1_000_000e18);
        assertEq(IFarmLike(farm).balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.depositToFarm(farm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 9_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),            0);
        assertEq(IFarmLike(farm).balanceOf(address(almProxy)), 1_000_000e18);
    }

}

contract MainnetControllerFarmWithdrawFailureTests is MainnetControllerFarmTestBase {

    function test_withdrawFromFarm_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.withdrawFromFarm(farm, 1_000_000e18);
    }

    function test_withdrawFromFarm_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawFromFarm(makeAddr("fake-farm"), 0);
    }

    function test_withdrawFromFarm_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_FARM_WITHDRAW(),
            farm
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usds), address(almProxy), 1_000_000e18);
        vm.startPrank(relayer);
        mainnetController.depositToFarm(farm, 1_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawFromFarm(farm, 1_000_000e18 + 1);

        mainnetController.withdrawFromFarm(farm, 1_000_000e18);
    }

}

contract MainnetControllerFarmWithdrawSuccessTests is MainnetControllerFarmTestBase {

    function test_withdrawFromFarm() external {
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_FARM_WITHDRAW(),
            farm
        );

        deal(address(usds), address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        mainnetController.depositToFarm(farm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                 0);
        assertEq(IFarmLike(farm).balanceOf(address(almProxy)),      1_000_000e18);
        assertEq(IERC20(Ethereum.SPK).balanceOf(address(almProxy)), 0);

        skip(1 days);

        vm.prank(relayer);
        mainnetController.withdrawFromFarm(farm, 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 9_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),                 1_000_000e18);
        assertEq(IFarmLike(farm).balanceOf(address(almProxy)),      0);
        assertEq(IERC20(Ethereum.SPK).balanceOf(address(almProxy)), 2930.857045118398e18);
    }

}
