// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { ICentrifugeV3VaultLike, IAsyncRedeemManagerLike } from "../../src/interfaces/CentrifugeInterfaces.sol";

import "./ForkTestBase.t.sol";

contract CentrifugeTestBase is ForkTestBase {

    address constant CENTRIFUGE_VAULT = 0x1121F4e21eD8B9BC1BB9A2952cDD8639aC897784; // DEJAAA_VAULT_USDC

    uint16  constant DESTINATION_CENTRIFUGE_ID = 5; // Avalanche Centrifuge ID

    ICentrifugeV3VaultLike centrifugeVault = ICentrifugeV3VaultLike(CENTRIFUGE_VAULT);

    IAsyncRedeemManagerLike manager;

    address root;
    address spoke;
    address vaultToken;

    uint64  poolId;
    bytes16 scId;

    function setUp() public override {
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

contract MainnetControllerTransferSharesCentrifugeFailureTests is CentrifugeTestBase {

    function test_transferSharesCentrifuge_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.startPrank(GROVE_PROXY);

        bytes32 target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_CENTRIFUGE_TRANSFER(),
                CENTRIFUGE_VAULT,
                DESTINATION_CENTRIFUGE_ID
            )),
            10_000_000e6,
            0
        );

        mainnetController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(vaultToken, address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for Centrifuge

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferSharesCentrifuge{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        mainnetController.transferSharesCentrifuge{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

        function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        vm.startPrank(GROVE_PROXY);

        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_CENTRIFUGE_TRANSFER(),
                CENTRIFUGE_VAULT,
                DESTINATION_CENTRIFUGE_ID
            )),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        // Setup token balances
        deal(vaultToken, address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for Centrifuge

        vm.startPrank(relayer);
        vm.expectRevert("MainnetController/centrifuge-id-not-configured");
        mainnetController.transferSharesCentrifuge{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

}

contract MainnetControllerTransferSharesCentrifugeSuccessTests is CentrifugeTestBase {

    event InitiateTransferShares(
        uint16 centrifugeId,
        uint64 indexed poolId,
        bytes16 indexed scId,
        address indexed sender,
        bytes32 destinationAddress,
        uint128 amount
    );

    function test_transferSharesCentrifuge() external {
        vm.startPrank(GROVE_PROXY);

        bytes32 target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_CENTRIFUGE_TRANSFER(),
                CENTRIFUGE_VAULT,
                DESTINATION_CENTRIFUGE_ID
            )),
            10_000_000e6,
            0
        );

        mainnetController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for Centrifuge

        // Issue shares at price 1.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            10_000_000e6,
            1e18
        );

        uint256 proxyBalanceBefore     = IERC20(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyBefore = IERC20(vaultToken).totalSupply();

        vm.expectEmit(address(spoke));
        emit InitiateTransferShares(
            DESTINATION_CENTRIFUGE_ID,
            poolId,
            scId,
            address(almProxy),
            target,
            10_000_000e6
        );

        vm.startPrank(relayer);
        mainnetController.transferSharesCentrifuge{value: 0.1 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        uint256 proxyBalanceAfter     = IERC20(vaultToken).balanceOf(address(almProxy));
        uint256 shareTotalSupplyAfter = IERC20(vaultToken).totalSupply();

        assertEq(proxyBalanceAfter,     proxyBalanceBefore     - 10_000_000e6);
        assertEq(shareTotalSupplyAfter, shareTotalSupplyBefore - 10_000_000e6);
    }

}
