// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { Address } from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { RateLimitLib } from "../../src/libraries/RateLimitLib.sol";
import { RolesLib }     from "../../src/libraries/RolesLib.sol";

import { ERC20Transfer } from "../../src/facets/ERC20Transfer.sol";
import { Roles }         from "../../src/facets/Roles.sol";

import { ALMProxy } from "../../src/ALMProxy.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IAssetTransferFunctions {
    function transferAsset(address token, address recipient, uint256 amount) external;
    function setAssetTransferRateLimit(address token, address recipient, uint256 maxAmount, uint256 slope, uint256 lastAmount, uint256 lastUpdated) external;
    function relayerRole() external view returns (bytes32 relayerRole);
    function getCurrentAssetTransferRateLimit(address token, address recipient) external view returns (uint256 currentRateLimit);
    function getAssetTransferRateLimitData(address token, address recipient) external view returns (RateLimitLib.RateLimitData memory rateLimitData);
}

contract ERC20TransferFacetTests is ForkTestBase {

    address receiver     = makeAddr("receiver");
    address unauthorized = makeAddr("unauthorized");

    address assetTransferFacet;

    function setUp() public override {
        super.setUp();

        assetTransferFacet = address(new ERC20Transfer());

        bytes4[] memory functionSelectors = new bytes4[](5);
        functionSelectors[0] = IAssetTransferFunctions.transferAsset.selector;
        functionSelectors[1] = IAssetTransferFunctions.setAssetTransferRateLimit.selector;
        functionSelectors[2] = IAssetTransferFunctions.relayerRole.selector;
        functionSelectors[3] = IAssetTransferFunctions.getCurrentAssetTransferRateLimit.selector;
        functionSelectors[4] = IAssetTransferFunctions.getAssetTransferRateLimitData.selector;

        ALMProxy.Implementation[] memory implementations = new ALMProxy.Implementation[](5);
        implementations[0] = ALMProxy.Implementation({
            implementation: assetTransferFacet,
            functionSelector: ERC20Transfer.transfer.selector
        });
        implementations[1] = ALMProxy.Implementation({
            implementation: assetTransferFacet,
            functionSelector: ERC20Transfer.setRateLimit.selector
        });
        implementations[2] = ALMProxy.Implementation({
            implementation: assetTransferFacet,
            functionSelector: ERC20Transfer.relayerRole.selector
        });
        implementations[3] = ALMProxy.Implementation({
            implementation: assetTransferFacet,
            functionSelector: ERC20Transfer.getCurrentRateLimit.selector
        });
        implementations[4] = ALMProxy.Implementation({
            implementation: assetTransferFacet,
            functionSelector: ERC20Transfer.getRateLimitData.selector
        });

        vm.startPrank(Ethereum.SPARK_PROXY);

        ALMProxy(almProxy).setImplementations(functionSelectors, implementations);

        ALMProxy(almProxy).delegateCall(
            assetTransferFacet,
            abi.encodeCall(ERC20Transfer.initialize, (ADMIN_ROLE, RELAYER_ROLE))
        );

        Roles(almProxy).grantRole(RELAYER_ROLE, relayer);

        vm.stopPrank();
    }

    function test_relayerRole() external {
        assertEq(IAssetTransferFunctions(almProxy).relayerRole(), RELAYER_ROLE);
    }

    function test_relayerHasRole() external {
        assertTrue(Roles(almProxy).hasRole(RELAYER_ROLE, relayer));
    }

    function test_setAssetTransferRateLimit_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            RolesLib.Roles_NotAuthorized.selector,
            unauthorized,
            ADMIN_ROLE
        ));
        vm.prank(unauthorized);
        IAssetTransferFunctions(almProxy).setAssetTransferRateLimit(address(0), address(0), 0, 0, 0, 0);
    }

    function test_setAssetTransferRateLimit() external {
        uint256 maxAmount = 5_000_000e18;
        uint256 slope = uint256(5_000_000e18) / 1 days;
        uint256 lastAmount = 5_000_000e18;
        uint256 lastUpdated = vm.getBlockTimestamp();

        vm.expectEmit(almProxy);
        emit ERC20Transfer.ERC20Transfer_RateLimitSet(
            Ethereum.SPARK_PROXY,
            address(Ethereum.USDC),
            receiver,
            maxAmount,
            slope,
            lastAmount,
            lastUpdated
        );

        vm.prank(Ethereum.SPARK_PROXY);
        IAssetTransferFunctions(almProxy).setAssetTransferRateLimit(Ethereum.USDC, receiver, maxAmount, slope, lastAmount, lastUpdated);

        assertEq(IAssetTransferFunctions(almProxy).getAssetTransferRateLimitData(Ethereum.USDC, receiver).maxAmount, maxAmount);
        assertEq(IAssetTransferFunctions(almProxy).getAssetTransferRateLimitData(Ethereum.USDC, receiver).slope, slope);
        assertEq(IAssetTransferFunctions(almProxy).getAssetTransferRateLimitData(Ethereum.USDC, receiver).lastAmount, lastAmount);
        assertEq(IAssetTransferFunctions(almProxy).getAssetTransferRateLimitData(Ethereum.USDC, receiver).lastUpdated, lastUpdated);
    }

    function test_transferAsset_notRelayer() external {
        vm.expectRevert(abi.encodeWithSelector(
            RolesLib.Roles_NotAuthorized.selector,
            address(this),
            RELAYER_ROLE
        ));
        IAssetTransferFunctions(almProxy).transferAsset(Ethereum.USDC, receiver, 1_000_000e6);
    }

    function test_transferAsset_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(
            ERC20Transfer.ERC20Transfer_RateLimitExceeded.selector,
            makeAddr("fake-token"),
            receiver,
            1e18,
            0
        ));
        IAssetTransferFunctions(almProxy).transferAsset(makeAddr("fake-token"), receiver, 1e18);
    }

    function test_transferAsset_rateLimitedBoundary() external {
        _setRateLimit(Ethereum.USDC);

        vm.expectRevert(abi.encodeWithSelector(
            ERC20Transfer.ERC20Transfer_RateLimitExceeded.selector,
            Ethereum.USDC,
            receiver,
            1_000_000e6 + 1,
            1_000_000e6
        ));
        vm.startPrank(relayer);
        IAssetTransferFunctions(almProxy).transferAsset(Ethereum.USDC, receiver, 1_000_000e6 + 1);
    }

    function test_transferAsset_transferFailedOnReturnFalse() external {
        address token = makeAddr("token");

        _setRateLimit(token);

        vm.mockCall(token, abi.encodeCall(IERC20.transfer, (receiver, 1e6)), abi.encode(false));

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(
            SafeERC20.SafeERC20FailedOperation.selector,
            token
        ));
        IAssetTransferFunctions(almProxy).transferAsset(token, receiver, 1e6);
    }

    function test_transferAsset_transferFailedOnRevert() external {
        address token = makeAddr("token");

        _setRateLimit(token);

        vm.mockCallRevert(token, abi.encodeCall(IERC20.transfer, (receiver, 1e6)), "");

        vm.prank(relayer);
        vm.expectRevert(Address.FailedInnerCall.selector);
        IAssetTransferFunctions(almProxy).transferAsset(token, receiver, 1e6);
    }

    function test_transferAsset() external {
        _setRateLimit(Ethereum.USDC);

        deal(Ethereum.USDC, almProxy, 1_000_000e6);

        assertEq(IERC20(Ethereum.USDC).balanceOf(receiver), 0);
        assertEq(IERC20(Ethereum.USDC).balanceOf(almProxy), 1_000_000e6);

        vm.prank(relayer);
        IAssetTransferFunctions(almProxy).transferAsset(Ethereum.USDC, receiver, 1_000_000e6);

        assertEq(IERC20(Ethereum.USDC).balanceOf(receiver), 1_000_000e6);
        assertEq(IERC20(Ethereum.USDC).balanceOf(almProxy), 0);
    }

    function test_transferAsset_successNoReturnData() external {
        _setRateLimit(Ethereum.USDT);

        deal(Ethereum.USDT, almProxy, 1_000_000e6);

        assertEq(IERC20(Ethereum.USDT).balanceOf(receiver), 0);
        assertEq(IERC20(Ethereum.USDT).balanceOf(almProxy), 1_000_000e6);

        vm.prank(relayer);
        IAssetTransferFunctions(almProxy).transferAsset(Ethereum.USDT, receiver, 1_000_000e6);

        assertEq(IERC20(Ethereum.USDT).balanceOf(receiver), 1_000_000e6);
        assertEq(IERC20(Ethereum.USDT).balanceOf(almProxy), 0);
    }

    function _setRateLimit(address token_) internal {
        vm.prank(Ethereum.SPARK_PROXY);
        IAssetTransferFunctions(almProxy).setAssetTransferRateLimit(
            token_,
            receiver,
            1_000_000e6,
            uint256(1_000_000e6) / 1 days,
            1_000_000e6,
            vm.getBlockTimestamp()
        );
    }

}
