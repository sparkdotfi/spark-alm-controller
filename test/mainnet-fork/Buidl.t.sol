// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IWhitelistLike {
    function addWallet(address account, string memory id) external;
    function registerInvestor(string memory id, string memory collisionHash) external;
}

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

contract MainnetControllerBUIDLTestBase is ForkTestBase {

    address buidlDeposit = makeAddr("buidlDeposit");

}

contract MainnetControllerDepositBUIDLFailureTests is MainnetControllerBUIDLTestBase {

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.transferAsset(address(usdc), buidlDeposit, 0);
    }

    function test_transferAsset_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_ASSET_TRANSFER(),
            address(usdc),
            address(buidlDeposit)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6 + 1);

        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);
    }

}

contract MainnetControllerDepositBUIDLSuccessTests is MainnetControllerBUIDLTestBase {

    function test_transferAsset() external {
        bytes32 key = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_ASSET_TRANSFER(),
            address(usdc),
            address(buidlDeposit)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(buidlDeposit),      0);

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(buidlDeposit),      1_000_000e6);
    }

}
