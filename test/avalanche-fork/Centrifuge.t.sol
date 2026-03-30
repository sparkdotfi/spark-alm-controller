// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey, makeAddressUint16Key } from "../../src/libraries/RateLimitHelpers.sol";

import {
    IAsyncRedeemManagerLike,
    IBalanceSheetLike,
    ICentrifugeV3ShareLike,
    ICentrifugeV3VaultLike,
    IFreelyTransferableHookLike,
    ISpokeLike
} from "../interfaces/Centrifuge.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

abstract contract Centrifuge_TestBase is ForkTestBase {

    address constant CENTRIFUGE_VAULT = 0xCF4C60066aAB54b3f750F94c2a06046d5466Ccf9; // deJAAA USDC Vault

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 constant REQUEST_ID = 0;

    ICentrifugeV3VaultLike centrifugeV3Vault = ICentrifugeV3VaultLike(CENTRIFUGE_VAULT);

    ICentrifugeV3ShareLike      vaultToken;
    IFreelyTransferableHookLike vaultTokenHook;
    IAsyncRedeemManagerLike     manager;
    IBalanceSheetLike           balanceSheet;
    ISpokeLike                  spoke;

    address globalEscrow;
    address poolEscrow;
    address root;

    uint64  poolId;
    bytes16 scId;
    uint128 usdcAssetId;


    function _getBlock() internal pure override returns (uint256) {
        return 65896755;  // July 22, 2025
    }

    function setUp() public virtual override {
        super.setUp();

        vaultToken     = ICentrifugeV3ShareLike(centrifugeV3Vault.share());
        vaultTokenHook = IFreelyTransferableHookLike(vaultToken.hook());
        manager        = IAsyncRedeemManagerLike(centrifugeV3Vault.manager());
        balanceSheet   = IBalanceSheetLike(manager.balanceSheet());
        spoke          = ISpokeLike(manager.spoke());

        root   = centrifugeV3Vault.root();
        poolId = centrifugeV3Vault.poolId();
        scId   = centrifugeV3Vault.scId();

        usdcAssetId = spoke.assetToId(centrifugeV3Vault.asset(), 0);

        globalEscrow = manager.globalEscrow();
        poolEscrow   = manager.poolEscrow(poolId);
    }

}

contract ForeignController_Centrifuge_RequestDepositERC7540_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);
    }

    function test_requestDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6 + 1);

        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdcAvalanche.allowance(address(almProxy), address(centrifugeV3Vault)), 0);

        uint256 initialEscrowBal = usdcAvalanche.balanceOf(globalEscrow);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdcAvalanche.allowance(address(almProxy), address(centrifugeV3Vault)), 0);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract ForeignController_Centrifuge_ClaimDepositERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_500_000e6, uint256(1_500_000e6) / 1 days);
    }

    function test_claimDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));
    }

    function test_claimDepositERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.claimDepositERC7540(makeAddr("fake-vault"));
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)),   0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into Centrifuge V3 Vault by supplying USDC
        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(globalEscrow),       initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Issue shares at price 2.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            500_000e6,
            2e18
        );

        // Fulfill request at price 2.0
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            1_000_000e6,
            500_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply + 500_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 500_000e6);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim shares
        vm.prank(ALM_RELAYER);
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 500_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

    function test_claimDepositERC7540_multipleRequests() external {
        deal(address(usdcAvalanche), address(almProxy), 1_500_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into Centrifuge V3 Vault by supplying USDC
        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another deposit into Centrifuge V3 Vault by supplying more USDC
        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 500_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 1_500_000e6);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Issue shares at price 2.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            750_000e6,
            2e18
        );

        // Fulfill both requests at price 2.0
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            1_500_000e6,
            750_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply + 750_000e6);

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 750_000e6);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim shares
        vm.prank(ALM_RELAYER);
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 750_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract ForeignController_Centrifuge_CancelDepositERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.cancelCentrifugeDepositRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        vm.prank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,       address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), false);

        vm.prank(ALM_RELAYER);
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,       address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelDeposit_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_DEPOSIT(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimCentrifugeCancelDepositRequest(address(centrifugeV3Vault));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidVault() external {
        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.claimCentrifugeCancelDepositRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = usdcAvalanche.balanceOf(globalEscrow);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.startPrank(ALM_RELAYER);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));
        vm.stopPrank();

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), true);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(root);
        manager.fulfillDepositRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            1_000_000e6,
            0,
            1_000_000e6
        );

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        vm.prank(ALM_RELAYER);
        foreignController.claimCentrifugeCancelDepositRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal);
    }

}

contract ForeignController_Centrifuge_RequestRedeemERC7540_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);
        spoke.updatePricePoolPerAsset(poolId, scId, usdcAssetId, 1e6, uint64(block.timestamp));
        spoke.updatePricePoolPerShare(poolId, scId, 1e18, uint64(block.timestamp));
        vm.stopPrank();

        key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.prank(root);
        vaultToken.mint(address(almProxy), 2_000_000e6);

        uint256 overBoundaryShares = centrifugeV3Vault.convertToShares(1_000_000e6 + 1);
        uint256 atBoundaryShares   = centrifugeV3Vault.convertToShares(1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), overBoundaryShares);

        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), atBoundaryShares);
    }

    function test_requestRedeemERC7540() external {
        uint256 shares = centrifugeV3Vault.convertToShares(1_000_000e6);

        vm.prank(root);
        vaultToken.mint(address(almProxy), shares);

        assertEq(shares, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(address(almProxy)), shares);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);  // Rounding

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), shares);
    }

}

contract ForeignController_Centrifuge_ClaimRedeemERC7540_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 2_000_000e6, uint256(2_000_000e6) / 1 days);
    }

    function test_claimRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));
    }

    function test_claimRedeemERC7540_invalidVault() external {
        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.claimRedeemERC7540(makeAddr("fake-vault"));
    }

    function test_claimRedeemERC7540_singleRequest() external {
        vm.prank(root);
        vaultToken.mint(address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request Centrifuge V3 Vault redemption
        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Deposit 2M USDC
        deal(address(usdcAvalanche), root, 2_000_000e6);
        vm.startPrank(root);
        usdcAvalanche.approve(address(balanceSheet), 2_000_000e6);
        balanceSheet.deposit(poolId, scId, address(usdcAvalanche), 0, 2_000_000e6);
        vm.stopPrank();

        // Revoke shares at price 2.0
        vm.prank(root);
        manager.revokedShares(
            poolId,
            scId,
            usdcAssetId,
            2_000_000e6,
            1_000_000e6,
            2e18
        );

        // Fulfill request at price 2.0
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            2_000_000e6,
            1_000_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply - 1_000_000e6);

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(usdcAvalanche.balanceOf(poolEscrow),        2_000_000e6);
        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim assets
        vm.prank(ALM_RELAYER);
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));

        assertEq(usdcAvalanche.balanceOf(poolEscrow),        0);
        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 2_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

    function test_claimRedeemERC7540_multipleRequests() external {
        vm.prank(root);
        vaultToken.mint(address(almProxy), 1_500_000e6);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(address(almProxy)), 1_500_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request Centrifuge V3 Vault redemption
        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        assertEq(vaultToken.balanceOf(address(almProxy)), 500_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another Centrifuge V3 Vault redemption
        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 500_000e6);

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 1_500_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 1_500_000e6);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Deposit 2M USDC
        deal(address(usdcAvalanche), root, 3_000_000e6);
        vm.startPrank(root);
        usdcAvalanche.approve(address(balanceSheet), 3_000_000e6);
        balanceSheet.deposit(poolId, scId, address(usdcAvalanche), 0, 3_000_000e6);
        vm.stopPrank();

        // Revoke shares at price 2.0
        vm.prank(root);
        manager.revokedShares(
            poolId,
            scId,
            usdcAssetId,
            3_000_000e6,
            1_500_000e6,
            2e18
        );

        // Fulfill both requests at price 2.0
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            3_000_000e6,
            1_500_000e6,
            0
        );

        assertEq(vaultToken.totalSupply(), totalSupply - 1_500_000e6);

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(usdcAvalanche.balanceOf(poolEscrow),        3_000_000e6);
        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim assets
        vm.prank(ALM_RELAYER);
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));

        assertEq(usdcAvalanche.balanceOf(poolEscrow),        0);
        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 3_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract ForeignController_Centrifuge_CancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.cancelCentrifugeRedeemRequest(makeAddr("fake-vault"));
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = 1_000_000e6;

        vm.prank(root);
        vaultToken.mint(address(almProxy), 1_000_000e6);

        vm.prank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,       address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), false);

        vm.prank(ALM_RELAYER);
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,       address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelRedeemRequest_Tests is Centrifuge_TestBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        bytes32 key = makeAddressKey(
            foreignController.LIMIT_7540_REDEEM(),
            address(centrifugeV3Vault)
        );

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.claimCentrifugeCancelRedeemRequest(address(centrifugeV3Vault));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidVault() external {
        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALM_RELAYER);
        foreignController.claimCentrifugeCancelRedeemRequest(makeAddr("fake-vault"));
    }

    function test_claimCentrifugeCancelRedeemRequest() external {
        uint256 shares = 1_000_000e6;

        vm.prank(root);
        vaultToken.mint(address(almProxy), shares);

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(address(almProxy)), shares);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.startPrank(ALM_RELAYER);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));
        vm.stopPrank();

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,         address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID,   address(almProxy)), true);
        assertEq(centrifugeV3Vault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(root);
        manager.fulfillRedeemRequest(
            poolId,
            scId,
            address(almProxy),
            usdcAssetId,
            0,
            0,
            uint128(shares)
        );

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), shares);

        vm.prank(ALM_RELAYER);
        foreignController.claimCentrifugeCancelRedeemRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(vaultToken.balanceOf(address(almProxy)), shares);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
    }

}

contract ForeignController_Centrifuge_TransferShares_Tests is Centrifuge_TestBase {

    bytes32 internal key;
    bytes32 internal target;

    uint16 internal constant DESTINATION_CENTRIFUGE_ID = 1; // Mainnet Centrifuge ID

    function setUp() public override {
        super.setUp();

        vm.startPrank(GROVE_EXECUTOR);

        key = makeAddressUint16Key(
            foreignController.LIMIT_CENTRIFUGE_TRANSFER(),
            CENTRIFUGE_VAULT,
            DESTINATION_CENTRIFUGE_ID
        );

        target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), address(almProxy), 10_000_000e6);
        deal(ALM_RELAYER, 1 ether);  // Gas cost for Centrifuge
    }

    function test_transferSharesCentrifuge_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALM_RELAYER);
        foreignController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(ALM_RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        vm.prank(GROVE_EXECUTOR);
        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, bytes32(0));

        vm.expectRevert("CentrifugeFacet/id-not-configured");
        vm.startPrank(ALM_RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge() external {
        // Issue shares at price 1.0
        vm.prank(root);
        manager.issuedShares(
            poolId,
            scId,
            10_000_000e6,
            1e18
        );

        uint256 proxyBalanceBefore     = vaultToken.balanceOf(address(almProxy));
        uint256 shareTotalSupplyBefore = vaultToken.totalSupply();

        vm.expectEmit(address(spoke));
        emit ISpokeLike.InitiateTransferShares(
            DESTINATION_CENTRIFUGE_ID,
            poolId,
            scId,
            address(almProxy),
            target,
            10_000_000e6
        );

        vm.startPrank(ALM_RELAYER);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        uint256 proxyBalanceAfter     = vaultToken.balanceOf(address(almProxy));
        uint256 shareTotalSupplyAfter = vaultToken.totalSupply();

        assertEq(proxyBalanceAfter,     proxyBalanceBefore     - 10_000_000e6);
        assertEq(shareTotalSupplyAfter, shareTotalSupplyBefore - 10_000_000e6);
    }

}
