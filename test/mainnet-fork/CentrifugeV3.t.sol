// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ICentrifugeFacet } from "../../src/facets/centrifuge/ICentrifugeFacet.sol";

import {
    IAsyncRedeemManagerLike,
    ICentrifugeV3VaultLike,
    IERC20Like
} from "../interfaces/Centrifuge.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract CentrifugeV3_TestBase is ForkTestBase {

    address constant CENTRIFUGE_VAULT = 0x1121F4e21eD8B9BC1BB9A2952cDD8639aC897784; // DEJAAA_VAULT_USDC

    uint16  constant DESTINATION_CENTRIFUGE_ID = 5; // Avalanche Centrifuge ID

    ICentrifugeV3VaultLike centrifugeVault = ICentrifugeV3VaultLike(CENTRIFUGE_VAULT);

    IAsyncRedeemManagerLike manager;

    address root;
    address spoke;
    address vaultToken;

    uint64  poolId;
    bytes16 scId;

    function setUp() public override virtual {
        super.setUp();

        root       = centrifugeVault.root();
        vaultToken = centrifugeVault.share();
        manager    = IAsyncRedeemManagerLike(centrifugeVault.manager());
        spoke      = manager.spoke();

        poolId = centrifugeVault.poolId();
        scId   = centrifugeVault.scId();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22968402;  // Jul 21, 2025
    }

}

contract MainnetController_CentrifugeV3_TransferShares_Tests is CentrifugeV3_TestBase {

    event InitiateTransferShares(
        uint16          centrifugeId,
        uint64  indexed poolId,
        bytes16 indexed scId,
        address indexed sender,
        bytes32         destinationAddress,
        uint128         amount
    );

    bytes32 internal target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

    function test_transferSharesCentrifuge_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        deal(allocator, 0.1 ether);

        vm.expectRevert("CentrifugeFacet/id-not-configured");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        rateLimits.setRateLimitData(
            mainnetController.centrifuge_getTransferRateLimitKey(CENTRIFUGE_VAULT, DESTINATION_CENTRIFUGE_ID, address(spoke)),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        // Setup token balances
        deal(vaultToken, address(almProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for Centrifuge

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge() external {
        vm.startPrank(SPARK_PROXY);

        mainnetController.centrifuge_setRecipient(DESTINATION_CENTRIFUGE_ID, target);

        rateLimits.setRateLimitData(
            mainnetController.centrifuge_getTransferRateLimitKey(CENTRIFUGE_VAULT, DESTINATION_CENTRIFUGE_ID, address(spoke)),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), address(almProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for Centrifuge

        // Issue shares at price 1.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            10_000_000e6,
            1e18
        );

        uint256 proxyBalanceBefore     = IERC20Like(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyBefore = IERC20Like(vaultToken).totalSupply();

        vm.expectEmit(address(spoke));
        emit InitiateTransferShares({
            centrifugeId       : DESTINATION_CENTRIFUGE_ID,
            poolId             : poolId,
            scId               : scId,
            sender             : address(almProxy),
            destinationAddress : target,
            amount             : 10_000_000e6
        });

        vm.expectEmit(address(mainnetController));
        emit ICentrifugeFacet.CentrifugeTransferShares(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(allocator);
        mainnetController.centrifuge_transferShares{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        uint256 proxyBalanceAfter     = IERC20Like(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyAfter = IERC20Like(vaultToken).totalSupply();

        assertEq(proxyBalanceAfter,     proxyBalanceBefore     - 10_000_000e6);
        assertEq(shareTotalSupplyAfter, shareTotalSupplyBefore - 10_000_000e6);
    }

}
