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

contract MainnetControllerRedeemBUIDLFailureTests is MainnetControllerBUIDLTestBase {

    address admin = 0xe01605f6b6dC593b7d2917F4a0940db2A625b09e;

    IWhitelistLike whitelist = IWhitelistLike(0x0Dac900f26DE70336f2320F7CcEDeE70fF6A1a5B);

    IBuidlLike buidl = IBuidlLike(0x7712c34205737192402172409a8F7ccef8aA2AEc);

    function test_redeemBUIDLCircleFacility_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);
    }

    function test_redeemBUIDLCircleFacility_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);
    }

    function test_redeemBUIDLCircleFacility_rateLimitsBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_BUIDL_REDEEM_CIRCLE(),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        // Set up success case
        vm.startPrank(admin);
        whitelist.registerInvestor("spark-almProxy", "collisionHash");
        whitelist.addWallet(address(almProxy), "spark-almProxy");
        buidl.issueTokens(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        skip(25 hours);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6 + 1);

        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);
    }

}

contract MainnetControllerRedeemBUIDLSuccessTests is MainnetControllerBUIDLTestBase {

    address admin = 0xe01605f6b6dC593b7d2917F4a0940db2A625b09e;

    IWhitelistLike whitelist = IWhitelistLike(0x0Dac900f26DE70336f2320F7CcEDeE70fF6A1a5B);

    IBuidlLike buidl = IBuidlLike(0x7712c34205737192402172409a8F7ccef8aA2AEc);

    function setUp() override public {
        super.setUp();

        vm.startPrank(admin);
        whitelist.registerInvestor("spark-almProxy", "collisionHash");
        whitelist.addWallet(address(almProxy), "spark-almProxy");
        vm.stopPrank();
    }

    function test_redeemBUIDLCircleFacility() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_BUIDL_REDEEM_CIRCLE(),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        vm.startPrank(admin);
        buidl.issueTokens(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        skip(25 hours);

        assertEq(buidl.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  0);

        vm.startPrank(relayer);
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);

        assertEq(buidl.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
    }

    function test_redeemBUIDLCircleFacility_timelockReset() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_BUIDL_REDEEM_CIRCLE(),
            2_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        vm.prank(admin);
        buidl.issueTokens(address(almProxy), 1_000_000e6);

        skip(24 hours);

        uint256 snapshot = vm.snapshot();

        // Can redeem after 24 hours
        vm.prank(relayer);
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);

        vm.revertTo(snapshot);

        vm.prank(admin);
        buidl.issueTokens(address(almProxy), 1);

        // Redeem of original 1_000_000e6 can still succeed
        vm.prank(relayer);
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);

        // Redeem of new 1 can fail
        vm.expectRevert("Under lock-up");
        vm.prank(relayer);
        mainnetController.redeemBUIDLCircleFacility(1);

        vm.revertTo(snapshot);

        vm.prank(admin);
        buidl.issueTokens(address(almProxy), 1);

        // Redeem of amount over original 1_000_000e6 will revert
        vm.prank(relayer);
        vm.expectRevert("Under lock-up");
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6 + 1);
    }

}

contract MainnetControllerDepositRedeemBUIDLE2ESuccessTests is MainnetControllerBUIDLTestBase {

    address admin = 0xe01605f6b6dC593b7d2917F4a0940db2A625b09e;

    IWhitelistLike whitelist = IWhitelistLike(0x0Dac900f26DE70336f2320F7CcEDeE70fF6A1a5B);

    IBuidlLike buidl = IBuidlLike(0x7712c34205737192402172409a8F7ccef8aA2AEc);

    function setUp() override public {
        super.setUp();

        vm.startPrank(admin);
        whitelist.registerInvestor("spark-almProxy", "collisionHash");
        whitelist.addWallet(address(almProxy), "spark-almProxy");
        vm.stopPrank();
    }

    function test_e2e_redeemBUIDLCircleFacility() public {
        bytes32 depositKey = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_ASSET_TRANSFER(),
            address(usdc),
            address(buidlDeposit)
        );

        bytes32 redeemKey = mainnetController.LIMIT_BUIDL_REDEEM_CIRCLE();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(redeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);

        // Step 1: Deposit into BUIDL

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(buidlDeposit),      0);

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(buidlDeposit),      1_000_000e6);

        // Step 2: BUIDL gets minted into proxy

        assertEq(buidl.balanceOf(address(almProxy)), 0);

        vm.startPrank(admin);
        buidl.issueTokens(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        assertEq(buidl.balanceOf(address(almProxy)), 1_000_000e6);

        // Step 3: Demostrate BUIDL can't be redeemed for 24 hours

        skip(24 hours - 1 seconds);

        vm.startPrank(relayer);
        vm.expectRevert("Under lock-up");
        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);

        skip(1 seconds);

        // Step 4: Redeem BUIDL after timelock is passed

        assertEq(rateLimits.getCurrentRateLimit(redeemKey), 1_000_000e6);

        assertEq(buidl.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(address(almProxy)),  0);

        mainnetController.redeemBUIDLCircleFacility(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(redeemKey), 0);

        assertEq(buidl.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
    }

}
