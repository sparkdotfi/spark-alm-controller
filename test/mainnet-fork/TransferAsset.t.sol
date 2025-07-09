// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { DssTest } from "dss-test/DssTest.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

import { ALMGlobals }              from "../../src/ALMGlobals.sol";
import { ALMProxy }                from "../../src/ALMProxy.sol";
import { RateLimits }              from "../../src/RateLimits.sol";
import { RateLimitHelpers }        from "../../src/RateLimitHelpers.sol";
import { TransferAssetController } from "../../src/TransferAssetController.sol";

contract TransferAssetControllerTestBase is DssTest {

    bytes32 public constant CONTROLLER = keccak256("CONTROLLER");
    bytes32 public constant RELAYER    = keccak256("RELAYER");

    address public relayer = makeAddr("relayer");

    address public buidlDeposit = makeAddr("buidlDeposit");

    IERC20 public usdc;

    ALMGlobals public globals;
    ALMProxy   public almProxy;
    RateLimits public rateLimits;

    TransferAssetController public transferAssetController;

    function setUp() public virtual {
        vm.createSelectFork(getChain("mainnet").rpcUrl);

        usdc = IERC20(Ethereum.USDC);

        almProxy   = new ALMProxy(Ethereum.SPARK_PROXY);
        rateLimits = new RateLimits(Ethereum.SPARK_PROXY);

        globals = new ALMGlobals(Ethereum.SPARK_PROXY, address(almProxy), address(rateLimits));

        transferAssetController = new TransferAssetController(address(globals));
        vm.startPrank(Ethereum.SPARK_PROXY);
        almProxy.grantRole(CONTROLLER, address(transferAssetController));
        rateLimits.grantRole(CONTROLLER, address(transferAssetController));
        globals.grantRole(RELAYER, relayer);
        vm.stopPrank();
    }

}

contract TransferAssetControllerFailureTests is TransferAssetControllerTestBase {

    function test_transferAsset_notRelayer() external {
        vm.expectRevert("TransferAssetController/not-relayer");
        transferAssetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        transferAssetController.transferAsset(address(usdc), buidlDeposit, 0);
    }

    function test_transferAsset_rateLimitsBoundary() external {
        bytes32 key = RateLimitHelpers.makeAssetDestinationKey(
            transferAssetController.LIMIT_ASSET_TRANSFER(),
            address(usdc),
            address(buidlDeposit)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        transferAssetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6 + 1);

        transferAssetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);
    }

}

contract TransferAssetControllerSuccessTests is TransferAssetControllerTestBase {

    function test_transferAsset() external {
        bytes32 key = RateLimitHelpers.makeAssetDestinationKey(
            transferAssetController.LIMIT_ASSET_TRANSFER(),
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
        transferAssetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(buidlDeposit),      1_000_000e6);
    }

}
