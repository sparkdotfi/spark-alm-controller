// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

import { IMapleTokenLike } from "../../src/MainnetController.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IMapleTokenExtended is IMapleTokenLike {
    function manager() external view returns (address);
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (address);
    function poolDelegate() external view returns (address);
}

interface IWithdrawalManagerLike {
    function processRedemptions(uint256 maxSharesToProcess) external;
}

contract MapleTestBase is ForkTestBase {

    IMapleTokenExtended constant syrup = IMapleTokenExtended(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);

    IPermissionManagerLike constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    uint256 SYRUP_CONVERTED_ASSETS;
    uint256 SYRUP_CONVERTED_SHARES;

    uint256 USDC_BAL_SYRUP;

    uint256 SYRUP_TOTAL_ASSETS;
    uint256 SYRUP_TOTAL_SUPPLY;

    bytes32 depositKey;
    bytes32 redeemKey;

    function setUp() override public {
        super.setUp();

        depositKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), address(syrup));
        redeemKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_MAPLE_REDEEM(), address(syrup));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);
        rateLimits.setRateLimitData(redeemKey,  1_000_000e6, uint256(1_000_000e6) / 1 days);
        mainnetController.setMaxSlippage(address(syrup), 1e18 - 1e4);  // Rounding slippage
        vm.stopPrank();

        // Maple onboarding process
        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(almProxy);
        booleans[0] = true;

        vm.startPrank(permissionManager.admin());
        permissionManager.setLenderAllowlist(
            syrup.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();

        SYRUP_CONVERTED_ASSETS = syrup.convertToAssets(1_000_000e6);
        SYRUP_CONVERTED_SHARES = syrup.convertToShares(1_000_000e6);

        SYRUP_TOTAL_ASSETS = syrup.totalAssets();
        SYRUP_TOTAL_SUPPLY = syrup.totalSupply();

        USDC_BAL_SYRUP = usdc.balanceOf(address(syrup));

        assertEq(SYRUP_CONVERTED_ASSETS, 1_066_100.425881e6);
        assertEq(SYRUP_CONVERTED_SHARES, 937_997.936895e6);

        assertEq(SYRUP_TOTAL_ASSETS, 59_578_045.544596e6);
        assertEq(SYRUP_TOTAL_SUPPLY, 55_884_083.805100e6);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21570000;  // Jan 7, 2024
    }

}

contract MainnetControllerDepositERC4626MapleFailureTests is MapleTestBase {

    function test_depositERC4626_maple_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositERC4626(address(syrup), 1_000_000e6);
    }

    function test_depositERC4626_maple_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositERC4626(address(syrup), 1_000_000e6);
    }

    function test_depositERC4626_maple_rateLimitBoundary() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositERC4626(address(syrup), 1_000_000e6 + 1);

        mainnetController.depositERC4626(address(syrup), 1_000_000e6);
    }

}

contract MainnetControllerDepositERC4626Tests is MapleTestBase {

    function test_depositERC4626_maple() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             USDC_BAL_SYRUP);

        assertEq(usdc.allowance(address(almProxy), address(syrup)),  0);

        assertEq(syrup.totalSupply(),                SYRUP_TOTAL_SUPPLY);
        assertEq(syrup.totalAssets(),                SYRUP_TOTAL_ASSETS);
        assertEq(syrup.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        assertEq(shares, SYRUP_CONVERTED_SHARES);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             USDC_BAL_SYRUP + 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(syrup)), 0);

        assertEq(syrup.totalSupply(),                SYRUP_TOTAL_SUPPLY + shares);
        assertEq(syrup.totalAssets(),                SYRUP_TOTAL_ASSETS + 1_000_000e6);
        assertEq(syrup.balanceOf(address(almProxy)), shares);
    }

}

contract MainnetControllerRequestMapleRedemptionFailureTests is MapleTestBase {

    function test_requestMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.requestMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_requestMapleRedemption_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.requestMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_requestMapleRedemption_rateLimitBoundary() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 5_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 5_000_000e6);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 5_000_000e6);

        uint256 overBoundaryShares = syrup.convertToShares(1_000_000e6 + 2);  // Rounding
        uint256 atBoundaryShares   = syrup.convertToShares(1_000_000e6 + 1);  // Rounding

        assertEq(syrup.convertToAssets(overBoundaryShares), 1_000_000e6 + 1);
        assertEq(syrup.convertToAssets(atBoundaryShares),   1_000_000e6);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.requestMapleRedemption(address(syrup), overBoundaryShares);

        mainnetController.requestMapleRedemption(address(syrup), atBoundaryShares);
    }

}

contract MainnetControllerRequestMapleRedemptionSuccessTests is MapleTestBase {

    function test_requestMapleRedemption() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        address withdrawalManager = IPoolManagerLike(syrup.manager()).withdrawalManager();

        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    0);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);
    }
}

contract MainnetControllerCancelMapleRedemptionFailureTests is MapleTestBase {

    function test_cancelMapleRedemption_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cancelMapleRedemption(address(syrup), 1_000_000e6);
    }

    function test_cancelMapleRedemption_invalidMapleToken() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.cancelMapleRedemption(makeAddr("fake-syrup"), 1_000_000e6);
    }

}

contract MainnetControllerCancelMapleRedemptionSuccessTests is MapleTestBase {

    function test_cancelMapleRedemption() public {
        address withdrawalManager = IPoolManagerLike(syrup.manager()).withdrawalManager();

        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.startPrank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),          0);

        mainnetController.cancelMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),          proxyShares);
    }

}

contract MainnetControllerMapleE2ETests is MapleTestBase {

    function test_e2e_mapleDepositAndRedeem() external {
        // Increase withdraw rate limit so interest can be accrued
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(redeemKey,  2_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdc), address(almProxy), 1_000_000e6);

        // --- Step 1: Deposit USDC into Maple ---

        assertEq(usdc.balanceOf(address(almProxy)),          1_000_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             USDC_BAL_SYRUP);

        assertEq(usdc.allowance(address(almProxy), address(syrup)),  0);

        assertEq(syrup.totalSupply(),                SYRUP_TOTAL_SUPPLY);
        assertEq(syrup.totalAssets(),                SYRUP_TOTAL_ASSETS);
        assertEq(syrup.balanceOf(address(almProxy)), 0);

        vm.prank(relayer);
        uint256 proxyShares = mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        assertEq(proxyShares, SYRUP_CONVERTED_SHARES);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(syrup)),             USDC_BAL_SYRUP + 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(syrup)), 0);

        assertEq(syrup.totalSupply(),                SYRUP_TOTAL_SUPPLY + proxyShares);
        assertEq(syrup.totalAssets(),                SYRUP_TOTAL_ASSETS + 1_000_000e6);
        assertEq(syrup.balanceOf(address(almProxy)), SYRUP_CONVERTED_SHARES);

        // --- Step 2: Request Redeem ---

        skip(1 days);  // Warp to accrue interest

        address withdrawalManager = IPoolManagerLike(syrup.manager()).withdrawalManager();

        uint256 totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    proxyShares);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), proxyShares);

        assertEq(syrup.balanceOf(address(withdrawalManager)),           totalEscrowedShares + proxyShares);
        assertEq(syrup.balanceOf(address(almProxy)),                    0);
        assertEq(syrup.allowance(address(almProxy), withdrawalManager), 0);

        // --- Step 3: Fulfill Redeem (done by Maple) ---

        skip(1 days);  // Warp to accrue more interest

        uint256 totalAssets    = syrup.totalAssets();
        uint256 withdrawAssets = syrup.convertToAssets(proxyShares);
        uint256 usdcPoolBal    = usdc.balanceOf(address(syrup));

        assertGt(totalAssets, SYRUP_TOTAL_ASSETS + 1_000_000e6);  // Interest accrued

        assertEq(withdrawAssets, 1_000_423.216342e6);  // Interest accrued

        assertEq(syrup.totalSupply(),                         SYRUP_TOTAL_SUPPLY + proxyShares);
        assertEq(syrup.totalAssets(),                         totalAssets);
        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares + proxyShares);

        assertEq(usdc.balanceOf(address(syrup)),    usdcPoolBal);
        assertEq(usdc.balanceOf(address(almProxy)), 0);

        // NOTE: `proxyShares` can be used in this case because almProxy is the only account using the
        //       `withdrawalManager` at this fork block. Usually `proccessRedemptions` requires
        //       `maxSharesToProcess` to include the shares of all accounts ahead of almProxy in
        //       queue plus almProxy's shares.
        vm.prank(IPoolManagerLike(syrup.manager()).poolDelegate());
        IWithdrawalManagerLike(withdrawalManager).processRedemptions(proxyShares);

        assertEq(syrup.totalSupply(),                         SYRUP_TOTAL_SUPPLY);
        assertEq(syrup.totalAssets(),                         totalAssets - withdrawAssets);
        assertEq(syrup.balanceOf(address(withdrawalManager)), totalEscrowedShares);

        assertEq(usdc.balanceOf(address(syrup)),    usdcPoolBal - withdrawAssets);
        assertEq(usdc.balanceOf(address(almProxy)), withdrawAssets);
    }
}
