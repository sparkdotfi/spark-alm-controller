// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IRestrictionManager {
    function updateMember(address token, address user, uint64 validUntil) external;
}

interface IInvestmentManager {
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

interface IERC7540 {
    function claimableDepositRequest(uint256 requestId, address controller)
        external view returns (uint256 assets);
    function claimableRedeemRequest(uint256 requestId, address controller)
        external view returns (uint256 shares);
    function pendingDepositRequest(uint256 requestId, address controller)
        external view returns (uint256 assets);
    function pendingRedeemRequest(uint256 requestId, address controller)
        external view returns (uint256 shares);
}

contract CentrifugeTestBase is ForkTestBase {

    address constant ESCROW                  = 0x0000000005F458Fd6ba9EEb5f365D83b7dA913dD;
    address constant INVESTMENT_MANAGER      = 0xE79f06573d6aF1B66166A926483ba00924285d20;
    address constant LTF_RESTRICTION_MANAGER = 0x4737C3f62Cc265e786b280153fC666cEA2fBc0c0;
    address constant LTF_TOKEN               = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address constant LTF_VAULT_USDC          = 0x1d01Ef1997d44206d839b78bA6813f60F1B3A970;
    address constant ROOT                    = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;

    bytes16 constant LTF_TRANCHE_ID = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant USDC_ASSET_ID  = 242333941209166991950178742833476896417;
    uint64  constant LTF_POOL_ID    = 4139607887;

    // Requests for Centrifuge pools are non-fungible and all have ID = 0
    uint256 constant REQUEST_ID = 0;

    IRestrictionManager restrictionManager = IRestrictionManager(LTF_RESTRICTION_MANAGER);
    IInvestmentManager  investmentManager  = IInvestmentManager(INVESTMENT_MANAGER);

    IERC20Mintable ltfToken = IERC20Mintable(LTF_TOKEN);
    IERC7540       ltfVault = IERC7540(LTF_VAULT_USDC);

    function _getBlock() internal pure override returns (uint256) {
        return 21570000;  // Jan 7, 2024
    }

}

contract MainnetControllerRequestDepositERC7540FailureTests is CentrifugeTestBase {

    function test_requestDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestDepositERC7540_rateLimitBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_7540_DEPOSIT(),
                address(ltfVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(ROOT);
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6 + 1);

        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);
    }
}

contract MainnetControllerRequestDepositERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.prank(ROOT);
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(), 
            address(ltfVault)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestDepositERC7540() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(ltfVault)), 0); 

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6); 
        assertEq(usdc.balanceOf(ESCROW),            0); 

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.allowance(address(almProxy), address(ltfVault)), 0); 

        assertEq(usdc.balanceOf(address(almProxy)), 0); 
        assertEq(usdc.balanceOf(ESCROW),            1_000_000e6);

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract MainnetControllerClaimDepositERC7540FailureTests is CentrifugeTestBase {

    function test_claimDepositERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimDepositERC7540(address(ltfVault));
    }

    function test_claimDepositERC7540_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.claimDepositERC7540(address(ltfVault));
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
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_DEPOSIT(), 
            address(ltfVault)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimDepositERC7540() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Request deposit into LTF by supplying USDC
        vm.prank(relayer);
        mainnetController.requestDepositERC7540(address(ltfVault), 1_000_000e6);

        uint256 totalSupply = ltfToken.totalSupply();

        assertEq(ltfToken.balanceOf(ESCROW),            0);
        assertEq(ltfToken.balanceOf(address(almProxy)), 0);

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(ltfVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        vm.prank(ROOT);
        investmentManager.fulfillDepositRequest(LTF_POOL_ID, LTF_TRANCHE_ID, address(almProxy), USDC_ASSET_ID, 1_000_000e6, 500_000e6);

        assertEq(ltfToken.totalSupply(),                totalSupply + 500_000e6);
        assertEq(ltfToken.balanceOf(ESCROW),            500_000e6);
        assertEq(ltfToken.balanceOf(address(almProxy)), 0);

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim shares
        vm.prank(relayer);
        mainnetController.claimDepositERC7540(address(ltfVault));

        assertEq(ltfToken.balanceOf(ESCROW),            0);
        assertEq(ltfToken.balanceOf(address(almProxy)), 500_000e6);

        assertEq(ltfVault.pendingDepositRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableDepositRequest(REQUEST_ID, address(almProxy)), 0);
    }

}

contract MainnetControllerRequestRedeemERC7540FailureTests is CentrifugeTestBase {

    function test_requestRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);
    }

    function test_requestRedeemERC7540_rateLimitsBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_7540_REDEEM(),
                address(ltfVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);
        ltfToken.mint(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6 + 1);

        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);
    }
}

contract MainnetControllerRequestRedeemERC7540SuccessTests is CentrifugeTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        vm.startPrank(ROOT);
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(), 
            address(ltfVault)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_requestRedeemERC7540() external {
        vm.prank(ROOT);
        ltfToken.mint(address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(ltfToken.balanceOf(address(almProxy)), 1_000_000e6); 
        assertEq(ltfToken.balanceOf(ESCROW),            0); 

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(ltfToken.balanceOf(address(almProxy)), 0); 
        assertEq(ltfToken.balanceOf(ESCROW),            1_000_000e6);

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);
    }

}

contract MainnetControllerClaimRedeemERC7540FailureTests is CentrifugeTestBase {

    function test_claimRedeemERC7540_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.claimRedeemERC7540(address(ltfVault));
    }

    function test_claimRedeemERC7540_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.claimRedeemERC7540(address(ltfVault));
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
        restrictionManager.updateMember(address(ltfToken), address(almProxy), type(uint64).max);
        vm.stopPrank();

        key = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_7540_REDEEM(), 
            address(ltfVault)
        );

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_claimRedeemERC7540() external {
        vm.prank(ROOT);
        ltfToken.mint(address(almProxy), 1_000_000e6);

        assertEq(ltfToken.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(ltfToken.balanceOf(ESCROW),            0);

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Request LTF redemption
        vm.prank(relayer);
        mainnetController.requestRedeemERC7540(address(ltfVault), 1_000_000e6);

        uint256 totalSupply = ltfToken.totalSupply();

        assertEq(ltfToken.balanceOf(address(almProxy)), 0);
        assertEq(ltfToken.balanceOf(ESCROW),            1_000_000e6);

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   1_000_000e6);
        assertEq(ltfVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);

        // Fulfill request at price 2.0
        deal(address(usdc), ESCROW, 2_000_000e6);
        vm.prank(ROOT);
        investmentManager.fulfillRedeemRequest(LTF_POOL_ID, LTF_TRANCHE_ID, address(almProxy), USDC_ASSET_ID, 2_000_000e6, 1_000_000e6);

        assertEq(ltfToken.totalSupply(),                totalSupply - 1_000_000e6);
        assertEq(ltfToken.balanceOf(address(almProxy)), 0);
        assertEq(ltfToken.balanceOf(ESCROW),            0);
        
        assertEq(usdc.balanceOf(ESCROW),            2_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 1_000_000e6);

        // Claim assets
        vm.prank(relayer);
        mainnetController.claimRedeemERC7540(address(ltfVault));

        assertEq(usdc.balanceOf(ESCROW),            0);
        assertEq(usdc.balanceOf(address(almProxy)), 2_000_000e6);

        assertEq(ltfVault.pendingRedeemRequest(REQUEST_ID, address(almProxy)),   0);
        assertEq(ltfVault.claimableRedeemRequest(REQUEST_ID, address(almProxy)), 0);
    }

}
