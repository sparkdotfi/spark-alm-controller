// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

import { ICentrifugeV3VaultLike } from "../../src/interfaces/CentrifugeInterfaces.sol";

import "./ForkTestBase.t.sol";


interface IRestrictionManager {
    function updateMember(address token, address user, uint64 validUntil) external;
}

interface IInvestmentManager {
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;
    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares
    ) external;
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

}

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract CentrifugeTestBase is ForkTestBase {

    address constant ESCROW                         = 0x0000000005F458Fd6ba9EEb5f365D83b7dA913dD;
    address constant INVESTMENT_MANAGER             = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;
    address constant JTREASURY_RESTRICTION_MANAGER  = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;
    address constant JTREASURY_TOKEN                = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address constant JTREASURY_VAULT_USDC           = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;
    address constant ROOT                           = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;

    bytes16 constant JTREASURY_TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant USDC_ASSET_ID        = 242333941209166991950178742833476896417;
    uint64  constant JTREASURY_POOL_ID    = 4139607887;

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 constant REQUEST_ID = 0;

    IInvestmentManager  investmentManager  = IInvestmentManager(INVESTMENT_MANAGER);
    IRestrictionManager restrictionManager = IRestrictionManager(JTREASURY_RESTRICTION_MANAGER);

    ICentrifugeV3VaultLike jTreasuryVault = ICentrifugeV3VaultLike(JTREASURY_VAULT_USDC);
    IERC20Mintable   jTreasuryToken = IERC20Mintable(JTREASURY_TOKEN);

    function _getBlock() internal pure override returns (uint256) {
        return 21988625;  // Mar 6, 2025
    }

}

contract MainnetControllerRequestDepositERC7540FailureTests is CentrifugeTestBase {

    function test_requestDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.startPrank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_7540_DEPOSIT(),
                address(jTreasuryVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6 + 1);

        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);
    }
}

contract MainnetControllerRequestDepositERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestDepositERC7540() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(jTreasuryVault)), 0);

        uint256 initialEscrowBal = usdc.balanceOf(ESCROW);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.allowance(address(almProxy), address(jTreasuryVault)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract MainnetControllerClaimDepositERC7540FailureTests is CentrifugeTestBase {

    function test_claimDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimDepositERC7540(address(jTreasuryVault));
    }

    function test_claimDepositERC7540_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.claimDepositERC7540(makeAddr("fake-vault"));
    }

}

contract MainnetControllerClaimDepositERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_500_000e6, uint256(1_500_000e6) / 1 days);
    }

    function test_claimDepositERC7540_singleRequest() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        vm.prank(ROOT);
        investmentManager.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_000_000e6,
            500_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply + 500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 500_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim shares
        vm.prank(relayer);
        mainnetController.claimDepositERC7540(address(jTreasuryVault));

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 500_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }


    function test_claimDepositERC7540_multipleRequests() external {
        deal(address(usdc), address(almProxy), 1_500_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into JTRSY by supplying USDC
        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another deposit into JTRSY by supplying more USDC
        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 500_000e6);

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_500_000e6);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill both requests at price 2.0
        vm.prank(ROOT);
        investmentManager.fulfillDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_500_000e6,
            750_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply + 750_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 750_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim shares
        vm.prank(relayer);
        mainnetController.claimDepositERC7540(address(jTreasuryVault));

        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 750_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract MainnetControllerCancelCentrifugeDepositFailureTests is CentrifugeTestBase {

    function test_cancelCentrifugeDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelCentrifugeDepositRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeDepositRequest_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.cancelCentrifugeDepositRequest(makeAddr("fake-vault"));
    }

}

contract MainnetControllerCancelCentrifugeDepositSuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeDepositRequest() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),       1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), false);

        vm.prank(relayer);
        mainnetController.cancelCentrifugeDepositRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),       1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract MainnetControllerClaimCentrifugeCancelDepositFailureTests is CentrifugeTestBase {

    function test_claimCentrifugeCancelDepositRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimCentrifugeCancelDepositRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelDepositRequest_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.claimCentrifugeCancelDepositRequest(makeAddr("fake-vault"));
    }

}

contract MainnetControllerClaimCentrifugeCancelDepositSuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelDepositRequest() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = usdc.balanceOf(ESCROW);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.startPrank(relayer);
        mainnetController.requestDepositERC7540(address(jTreasuryVault), 1_000_000e6);
        mainnetController.cancelCentrifugeDepositRequest(address(jTreasuryVault));
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         1_000_000e6);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   true);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        investmentManager.fulfillCancelDepositRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            1_000_000e6,
            1_000_000e6
        );

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.claimCentrifugeCancelDepositRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelDepositRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelDepositRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ESCROW),            initialEscrowBal);
    }

}

contract MainnetControllerRequestRedeemERC7540FailureTests is CentrifugeTestBase {

    function test_requestRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.startPrank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_7540_REDEEM(),
                address(jTreasuryVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);
        jTreasuryToken.mint(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        uint256 overBoundaryShares = jTreasuryVault.convertToShares(1_000_000e6 + 3);
        uint256 atBoundaryShares   = jTreasuryVault.convertToShares(1_000_000e6 + 1);

        assertEq(jTreasuryVault.convertToAssets(overBoundaryShares), 1_000_000e6 + 2);
        assertEq(jTreasuryVault.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), overBoundaryShares);

        mainnetController.requestRedeemERC7540(address(jTreasuryVault), atBoundaryShares);
    }
}

contract MainnetControllerRequestRedeemERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        assertEq(shares, 948_558.832635e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), shares);

        assertEq(rateLimits.getCurrentRateLimit(key), 1);  // Rounding

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), shares);
    }

}

contract MainnetControllerClaimRedeemERC7540FailureTests is CentrifugeTestBase {

    function test_claimRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimRedeemERC7540(address(jTreasuryVault));
    }

    function test_claimRedeemERC7540_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.claimRedeemERC7540(makeAddr("fake-vault"));
    }

}

contract MainnetControllerClaimRedeemERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 2_000_000e6, uint256(2_000_000e6) / 1 days);
    }

    function test_claimRedeemERC7540_singleRequest() external {
        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), 1_000_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request JTRSY redemption
        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        deal(address(usdc), ESCROW, 2_000_000e6);
        vm.prank(ROOT);
        investmentManager.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            2_000_000e6,
            1_000_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply - 1_000_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(usdc.balanceOf(ESCROW),            2_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim assets
        vm.prank(relayer);
        mainnetController.claimRedeemERC7540(address(jTreasuryVault));

        assertEq(usdc.balanceOf(ESCROW),            0);
        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

    function test_claimRedeemERC7540_multipleRequests() external {
        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), 1_500_000e6);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 1_500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request JTRSY redemption
        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), 1_000_000e6);

        uint256 totalSupply = jTreasuryToken.totalSupply();

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 500_000e6);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request another JTRSY redemption
        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), 500_000e6);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + 1_500_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_500_000e6);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill both requests at price 2.0
        deal(address(usdc), ESCROW, 3_000_000e6);
        vm.prank(ROOT);
        investmentManager.fulfillRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            3_000_000e6,
            1_500_000e6
        );

        assertEq(jTreasuryToken.totalSupply(),                totalSupply - 1_500_000e6);
        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(usdc.balanceOf(ESCROW),            3_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_500_000e6);

        // Claim assets
        vm.prank(relayer);
        mainnetController.claimRedeemERC7540(address(jTreasuryVault));

        assertEq(usdc.balanceOf(ESCROW),            0);
        assertEq(usdc.balanceOf(address(almProxy)), 3_000_000e6);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(jTreasuryVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract MainnetControllerCancelCentrifugeRedeemRequestFailureTests is CentrifugeTestBase {

    function test_cancelCentrifugeRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelCentrifugeRedeemRequest(address(jTreasuryVault));
    }

    function test_cancelCentrifugeRedeemRequest_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.cancelCentrifugeRedeemRequest(makeAddr("fake-vault"));
    }

}

contract MainnetControllerCancelCentrifugeRedeemRequestSuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_cancelCentrifugeRedeemRequest() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),       shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), false);

        vm.prank(relayer);
        mainnetController.cancelCentrifugeRedeemRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),       shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)), true);
    }

}

contract MainnetControllerClaimCentrifugeCancelRedeemRequestFailureTests is CentrifugeTestBase {

    function test_claimCentrifugeCancelRedeemRequest_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimCentrifugeCancelRedeemRequest(address(jTreasuryVault));
    }

    function test_claimCentrifugeCancelRedeemRequest_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.claimCentrifugeCancelRedeemRequest(makeAddr("fake-vault"));
    }

}

contract MainnetControllerClaimCentrifugeCancelRedeemRequestSuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(jTreasuryToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(),
            address(jTreasuryVault)
        );

        vm.prank(Ethereum.GROVE_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimCentrifugeCancelRedeemRequest() external {
        uint256 shares = jTreasuryVault.convertToShares(1_000_000e6);

        vm.prank(ROOT);
        jTreasuryToken.mint(address(almProxy), shares);

        uint256 initialEscrowBal = jTreasuryToken.balanceOf(ESCROW);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.startPrank(relayer);
        mainnetController.requestRedeemERC7540(address(jTreasuryVault), shares);
        mainnetController.cancelCentrifugeRedeemRequest(address(jTreasuryVault));
        vm.stopPrank();

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), 0);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal + shares);

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         shares);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   true);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill cancelation request
        vm.prank(ROOT);
        investmentManager.fulfillCancelRedeemRequest(
            JTREASURY_POOL_ID,
            JTREASURY_TRANCHE_ID,
            address(almProxy),
            USDC_ASSET_ID,
            uint128(shares)
        );

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), shares);

        vm.prank(relayer);
        mainnetController.claimCentrifugeCancelRedeemRequest(address(jTreasuryVault));

        assertEq(jTreasuryVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),         0);
        assertEq(jTreasuryVault.pendingCancelRedeemRequest(REQUEST_ID, address(almProxy)),   false);
        assertEq(jTreasuryVault.claimableCancelRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        assertEq(jTreasuryToken.balanceOf(address(almProxy)), shares);
        assertEq(jTreasuryToken.balanceOf(ESCROW),            initialEscrowBal);
    }

}
