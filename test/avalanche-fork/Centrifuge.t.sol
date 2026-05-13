// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ICentrifugeFacet } from "../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { IERC7540Facet }    from "../../src/facets/erc7540/IERC7540Facet.sol";

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

        key = foreignController.getERC7540RequestDepositRateLimitKey(address(centrifugeV3Vault), USDC_AVALANCHE);

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);
    }

    function test_requestDepositERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6 + 1);

        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestDepositERC7540() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdcAvalanche.allowance(address(almProxy), address(centrifugeV3Vault)), 0);

        uint256 initialEscrowBal = usdcAvalanche.balanceOf(globalEscrow);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit(address(centrifugeV3Vault), 1_000_000e6);

        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdcAvalanche.allowance(address(almProxy), address(centrifugeV3Vault)), 0);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract ForeignController_Centrifuge_ClaimDepositERC7540_Tests is Centrifuge_TestBase {

    bytes32 requestDepositKey;
    bytes32 claimDepositKey;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        requestDepositKey = foreignController.getERC7540RequestDepositRateLimitKey(address(centrifugeV3Vault), USDC_AVALANCHE);
        claimDepositKey   = foreignController.getERC7540ClaimDepositRateLimitKey(address(centrifugeV3Vault));

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestDepositKey, 1_500_000e6, uint256(1_500_000e6) / 1 days);
        rateLimits.setRateLimitData(claimDepositKey,   1_500_000e6, uint256(1_500_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimDepositERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));
    }

    function test_claimDepositERC7540_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(claimDepositKey, 0, 0);

        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into Centrifuge V3 Vault by supplying USDC
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(centrifugeV3Vault),
            assets : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540ClaimDeposit(address(centrifugeV3Vault), 500_000e6);

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(centrifugeV3Vault),
            assets : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        uint256 initialEscrowBal = vaultToken.balanceOf(globalEscrow);

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 0);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another deposit into Centrifuge V3 Vault by supplying more USDC
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(centrifugeV3Vault),
            assets : 500_000e6
        });

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540ClaimDeposit({
            token  : address(centrifugeV3Vault),
            shares : 750_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.claimDepositERC7540(address(centrifugeV3Vault));

        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal);
        assertEq(vaultToken.balanceOf(address(almProxy)), 750_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract ForeignController_Centrifuge_CancelDepositERC7540_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = foreignController.getCentrifugeCancelDepositRateLimitKey(address(centrifugeV3Vault));

        bytes32 requestDepositKey = foreignController.getERC7540RequestDepositRateLimitKey(
            address(centrifugeV3Vault),
            USDC_AVALANCHE
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestDepositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,               1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_cancelCentrifugeDepositRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeDepositRequest_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(centrifugeV3Vault),
            assets : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,       address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), false);

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeCancelDepositRequest(address(centrifugeV3Vault));

        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,       address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelDeposit_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = foreignController.getCentrifugeClaimCancelDepositRateLimitKey(address(centrifugeV3Vault));

        bytes32 requestDepositKey = foreignController.getERC7540RequestDepositRateLimitKey(
            address(centrifugeV3Vault),
            USDC_AVALANCHE
        );

        bytes32 cancelDepositKey = foreignController.getCentrifugeCancelDepositRateLimitKey(
            address(centrifugeV3Vault)
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestDepositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(cancelDepositKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,               1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimCentrifugeCancelDepositRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.claimCentrifugeCancelDepositRequest(address(centrifugeV3Vault));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.claimCentrifugeCancelDepositRequest(address(centrifugeV3Vault));
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(address(usdcAvalanche), address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = usdcAvalanche.balanceOf(globalEscrow);

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 0);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), false);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestDeposit({
            token  : address(centrifugeV3Vault),
            assets : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.requestDepositERC7540(address(centrifugeV3Vault), 1_000_000e6);

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeCancelDepositRequest({ token: address(centrifugeV3Vault) });

        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeDepositRequest(address(centrifugeV3Vault));

        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 0);
        assertEq(usdcAvalanche.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingDepositRequest(REQUEST_ID,         address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.pendingCancelDepositRequest(REQUEST_ID,   address(almProxy)), true);
        assertEq(centrifugeV3Vault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancellation request
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

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeClaimCancelDepositRequest(address(centrifugeV3Vault), 1_000_000e6);

        vm.prank(ALLOCATOR);
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

        key = foreignController.getERC7540RequestRedeemRateLimitKey(address(centrifugeV3Vault));

        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.prank(root);
        vaultToken.mint(address(almProxy), 2_000_000e6);

        uint256 overBoundaryShares = centrifugeV3Vault.convertToShares(1_000_000e6 + 1);
        uint256 atBoundaryShares   = centrifugeV3Vault.convertToShares(1_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), overBoundaryShares);

        vm.prank(ALLOCATOR);
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

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem(address(centrifugeV3Vault), shares);

        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);  // Rounding

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), shares);
    }

}

contract ForeignController_Centrifuge_ClaimRedeemERC7540_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = foreignController.getERC7540ClaimRedeemRateLimitKey(address(centrifugeV3Vault));

        bytes32 requestRedeemKey = foreignController.getERC7540RequestRedeemRateLimitKey(
            address(centrifugeV3Vault)
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestRedeemKey, 2_000_000e6, uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              2_000_000e6, uint256(2_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimRedeemERC7540_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));
    }

    function test_claimRedeemERC7540_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("ERC7540Facet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(centrifugeV3Vault),
            shares : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540ClaimRedeem(address(centrifugeV3Vault), 2_000_000e6);

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(centrifugeV3Vault),
            shares : 1_000_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), 1_000_000e6);

        uint256 totalSupply = vaultToken.totalSupply();

        assertEq(vaultToken.balanceOf(address(almProxy)), 500_000e6);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + 1_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 1_000_000e6);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another Centrifuge V3 Vault redemption
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(centrifugeV3Vault),
            shares : 500_000e6
        });

        vm.prank(ALLOCATOR);
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
        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540ClaimRedeem({
            token  : address(centrifugeV3Vault),
            assets : 3_000_000e6
        });

        vm.prank(ALLOCATOR);
        foreignController.claimRedeemERC7540(address(centrifugeV3Vault));

        assertEq(usdcAvalanche.balanceOf(poolEscrow),        0);
        assertEq(usdcAvalanche.balanceOf(address(almProxy)), 3_000_000e6);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,   address(almProxy)), 0);
        assertEq(centrifugeV3Vault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract ForeignController_Centrifuge_CancelRedeemRequest_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = foreignController.getCentrifugeCancelRedeemRateLimitKey(address(centrifugeV3Vault));

        bytes32 requestRedeemKey = foreignController.getERC7540RequestRedeemRateLimitKey(
            address(centrifugeV3Vault)
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestRedeemKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_cancelCentrifugeRedeemRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeRedeemRequest_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = 1_000_000e6;

        vm.prank(root);
        vaultToken.mint(address(almProxy), 1_000_000e6);

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(centrifugeV3Vault),
            shares : shares
        });

        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,       address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), false);

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeCancelRedeemRequest(address(centrifugeV3Vault));

        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,       address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract ForeignController_Centrifuge_ClaimCancelRedeemRequest_Tests is Centrifuge_TestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(root);
        vaultTokenHook.updateMember(address(vaultToken), address(almProxy), type(uint64).max);

        key = foreignController.getCentrifugeClaimCancelRedeemRateLimitKey(address(centrifugeV3Vault));

        bytes32 requestRedeemKey = foreignController.getERC7540RequestRedeemRateLimitKey(
            address(centrifugeV3Vault)
        );

        bytes32 cancelRedeemKey = foreignController.getCentrifugeCancelRedeemRateLimitKey(
            address(centrifugeV3Vault)
        );

        vm.startPrank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(requestRedeemKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(cancelRedeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(key,              1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();
    }

    function test_claimCentrifugeCancelRedeemRequest_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.claimCentrifugeCancelRedeemRequest(address(centrifugeV3Vault));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidAction() external {
        vm.prank(GROVE_EXECUTOR);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("CentrifugeFacet/invalid-action");
        vm.prank(ALLOCATOR);
        foreignController.claimCentrifugeCancelRedeemRequest(address(centrifugeV3Vault));
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

        vm.expectEmit(address(foreignController));
        emit IERC7540Facet.ERC7540RequestRedeem({
            token  : address(centrifugeV3Vault),
            shares : shares
        });

        vm.prank(ALLOCATOR);
        foreignController.requestRedeemERC7540(address(centrifugeV3Vault), shares);

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeCancelRedeemRequest({ token: address(centrifugeV3Vault) });

        vm.prank(ALLOCATOR);
        foreignController.cancelCentrifugeRedeemRequest(address(centrifugeV3Vault));

        assertEq(vaultToken.balanceOf(address(almProxy)), 0);
        assertEq(vaultToken.balanceOf(globalEscrow),      initialEscrowBal + shares);

        assertEq(centrifugeV3Vault.pendingRedeemRequest(REQUEST_ID,         address(almProxy)), shares);
        assertEq(centrifugeV3Vault.pendingCancelRedeemRequest(REQUEST_ID,   address(almProxy)), true);
        assertEq(centrifugeV3Vault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancellation request
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

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeClaimCancelRedeemRequest(address(centrifugeV3Vault), shares);

        vm.prank(ALLOCATOR);
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

        key = foreignController.getCentrifugeTransferRateLimitKey(
            CENTRIFUGE_VAULT,
            DESTINATION_CENTRIFUGE_ID,
            address(spoke)
        );

        target = bytes32(uint256(uint160(makeAddr("centrifugeRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        vm.stopPrank();

        // Setup token balances
        deal(address(vaultToken), address(almProxy), 10_000_000e6);
        deal(ALLOCATOR, 1 ether);  // Gas cost for Centrifuge
    }

    function test_transferSharesCentrifuge_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_zeroMaxAmount() external {
        vm.startPrank(GROVE_EXECUTOR);

        rateLimits.setRateLimitData(key, 0, 0);

        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(ALLOCATOR);
        foreignController.transferSharesCentrifuge(CENTRIFUGE_VAULT, 1_000_000e6, DESTINATION_CENTRIFUGE_ID);
    }

    function test_transferSharesCentrifuge_rateLimitedBoundary() external {
        vm.prank(GROVE_EXECUTOR);
        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(ALLOCATOR);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6 + 1,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(ALLOCATOR);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge_invalidCentrifugeId() external {
        vm.expectRevert("CentrifugeFacet/id-not-configured");
        vm.prank(ALLOCATOR);
        foreignController.transferSharesCentrifuge{value: 0.5 ether}(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );
    }

    function test_transferSharesCentrifuge() external {
        vm.prank(GROVE_EXECUTOR);
        foreignController.setCentrifugeRecipient(DESTINATION_CENTRIFUGE_ID, target);

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
        emit ISpokeLike.InitiateTransferShares({
            centrifugeId       : DESTINATION_CENTRIFUGE_ID,
            poolId             : poolId,
            scId               : scId,
            sender             : address(almProxy),
            destinationAddress : target,
            amount             : 10_000_000e6
        });

        vm.expectEmit(address(foreignController));
        emit ICentrifugeFacet.CentrifugeTransferShares(
            CENTRIFUGE_VAULT,
            10_000_000e6,
            DESTINATION_CENTRIFUGE_ID
        );

        vm.prank(ALLOCATOR);
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
