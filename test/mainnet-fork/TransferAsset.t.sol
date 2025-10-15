// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract MockToken is ERC20 {

    constructor() ERC20("MockToken", "MockToken") {}

    // Overriding transfer to return false to simulate a failed transfer
    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(_msgSender(), to, value);
        return false;
    }

}

contract TransferAssetBaseTest is ForkTestBase {

    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(usdc),
                receiver
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

}

contract MainnetControllerTransferAssetFailureTests is TransferAssetBaseTest {

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.transferAsset(makeAddr("fake-token"), receiver, 1e18);
    }

    function test_transferAsset_rateLimitedBoundary() external {
        deal(address(usdc), address(almProxy), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6 + 1);

        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);
    }

    function test_transferAsset_transferFailed() external {
        MockToken token = new MockToken();

        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(token),
                receiver
            ),
            1_000_000e18,
            uint256(1_000_000e18) / 1 days
        );

        vm.stopPrank();

        deal(address(token), address(almProxy), 1_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("MainnetController/transfer-failed");
        mainnetController.transferAsset(address(token), receiver, 1_000_000e18);
    }

}

contract MainnetControllerTransferAssetSuccessTests is TransferAssetBaseTest {

    function test_transferAsset() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), receiver, 1_000_000e6);

        assertEq(usdc.balanceOf(address(receiver)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);
    }

}
