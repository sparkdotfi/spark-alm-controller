// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import "./ForkTestBase.t.sol";

contract SUSDSTestBase is ForkTestBase {

    uint256 SUSDS_CONVERTED_ASSETS;
    uint256 SUSDS_CONVERTED_SHARES;

    uint256 SUSDS_TOTAL_ASSETS;
    uint256 SUSDS_TOTAL_SUPPLY;

    uint256 SUSDS_DRIP_AMOUNT;

    bytes32 depositKey;
    bytes32 withdrawKey;

    function setUp() override public {
        super.setUp();

        depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  Ethereum.SUSDS);
        withdrawKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), Ethereum.SUSDS);

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(), 10_000_000e18, uint256(10_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.setMaxExchangeRate(address(susds), susds.convertToShares(1e18), 1.2e18);
        vm.stopPrank();

        SUSDS_CONVERTED_ASSETS = susds.convertToAssets(1e18);
        SUSDS_CONVERTED_SHARES = susds.convertToShares(1e18);

        SUSDS_TOTAL_ASSETS = susds.totalAssets();
        SUSDS_TOTAL_SUPPLY = susds.totalSupply();

        // Setting this value directly because susds.drip() fails in setUp with
        // StateChangeDuringStaticCall and it is unclear why, something related to foundry.
        SUSDS_DRIP_AMOUNT = 849.454677397481388011e18;

        assertEq(SUSDS_CONVERTED_ASSETS, 1.003430776383974596e18);
        assertEq(SUSDS_CONVERTED_SHARES, 0.996580953599671364e18);

        assertEq(SUSDS_TOTAL_ASSETS, 485_597_342.757158870618550128e18);
        assertEq(SUSDS_TOTAL_SUPPLY, 483_937_062.910395855928183397e18);
    }

}

contract MainnetControllerDepositERC4626FailureTests is SUSDSTestBase {

    function test_depositERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.depositERC4626(address(susds), 1e18, 0);
    }

    function test_depositERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.depositERC4626(address(susds), 1e18, 0);
    }

    function test_depositERC4626_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositERC4626(makeAddr("fake-token"), 1e18, 0);
    }

    function test_depositERC4626_rateLimitBoundary() external {
        vm.startPrank(relayer);

        mainnetController.mintUSDS(5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositERC4626(address(susds), 5_000_000e18 + 1, 0);

        mainnetController.depositERC4626(address(susds), 5_000_000e18, 0);

        vm.stopPrank();
    }

    function test_depositERC4626_exchangeRateBoundary() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(5_000_000e18);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(
            address(susds),
            susds.convertToShares(5_000_000e18),
            5_000_000e18 - 1
        );
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("MC/exchange-rate-too-high");
        mainnetController.depositERC4626(address(susds), 5_000_000e18, 0);

        vm.startPrank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(
            address(susds),
            susds.convertToShares(5_000_000e18),
            5_000_000e18
        );
        vm.stopPrank();

        vm.prank(relayer);
        mainnetController.depositERC4626(address(susds), 5_000_000e18, 0);
    }

    function test_depositERC4626_zeroExchangeRate() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(5_000_000e18);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxExchangeRate(address(susds), 0, 0);

        vm.prank(relayer);
        vm.expectRevert("MC/exchange-rate-too-high");
        mainnetController.depositERC4626(address(susds), 5_000_000e18, 0);
    }

    function test_depositERC4626_minSharesOutNotMet() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1e18);

        vm.prank(relayer);
        vm.expectRevert("MC/min-shares-out-not-met");
        mainnetController.depositERC4626(address(susds), 1e18, 1e18);
    }

    function test_depositERC4626_minSharesOutNotMetBoundary() external {
        uint256 overBoundaryShares = susds.convertToShares(5_000_000e18 + 1);
        uint256 atBoundaryShares   = susds.convertToShares(5_000_000e18);

        vm.startPrank(relayer);

        mainnetController.mintUSDS(5_000_000e18);

        vm.expectRevert("MC/min-shares-out-not-met");
        mainnetController.depositERC4626(address(susds), 5_000_000e18, overBoundaryShares);

        mainnetController.depositERC4626(address(susds), 5_000_000e18, atBoundaryShares);
        vm.stopPrank();
    }

}

contract MainnetControllerDepositERC4626Tests is SUSDSTestBase {

    function test_depositERC4626() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1e18);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS);

        assertEq(usds.allowance(address(buffer),   address(vault)),  type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);

        vm.record();

        vm.prank(relayer);
        uint256 shares = mainnetController.depositERC4626(
            address(susds),
            1e18,
            SUSDS_CONVERTED_SHARES
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(shares, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)), 0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + shares);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);
    }

}

contract MainnetControllerWithdrawERC4626FailureTests is SUSDSTestBase {

    function test_withdrawERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.withdrawERC4626(address(susds), 1e18, 1e18);
    }

    function test_withdrawERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.withdrawERC4626(address(susds), 1e18, 1e18);
    }

    function test_withdrawERC4626_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawERC4626(makeAddr("fake-token"), 1e18, 1e18);
    }

    function test_withdrawERC4626_rateLimitBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();

        vm.startPrank(relayer);

        mainnetController.mintUSDS(10_000_000e18);
        mainnetController.depositERC4626(address(susds), 10_000_000e18, 0);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawERC4626(address(susds), 5_000_000e18 + 1, 5_000_000e18 + 1);

        mainnetController.withdrawERC4626(address(susds), 5_000_000e18, 5_000_000e18);

        vm.stopPrank();
    }

    function test_withdrawERC4626_maxSharesInNotMet() external {
        vm.startPrank(relayer);
        mainnetController.mintUSDS(2e18);
        mainnetController.depositERC4626(address(susds), 2e18, 0);

        vm.expectRevert("MC/max-shares-in-not-met");
        mainnetController.withdrawERC4626(address(susds), 1e18, 0);
        vm.stopPrank();
    }

    function test_withdrawERC4626_maxSharesInNotMetBoundary() external {
        // Because of rounding 1_000_000e18 is under boundary, 1_000_000e18 + 1 is at boundary

        uint256 underBoundaryShares = susds.convertToShares(1_000_000e18);
        uint256 atBoundaryShares    = susds.convertToShares(1_000_000e18 + 1);

        vm.startPrank(relayer);

        mainnetController.mintUSDS(2_000_000e18);
        mainnetController.depositERC4626(address(susds), 2_000_000e18, 0);

        vm.expectRevert("MC/max-shares-in-not-met");
        mainnetController.withdrawERC4626(address(susds), 1_000_000e18, underBoundaryShares);

        mainnetController.withdrawERC4626(address(susds), 1_000_000e18, atBoundaryShares);
        vm.stopPrank();
    }

}

contract MainnetControllerWithdrawERC4626Tests is SUSDSTestBase {

    function test_withdrawERC4626() external {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_4626_DEPOSIT(),
            Ethereum.SUSDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_4626_WITHDRAW(),
            Ethereum.SUSDS
        );

        vm.startPrank(relayer);
        mainnetController.mintUSDS(1e18);
        mainnetController.depositERC4626(address(susds), 1e18, SUSDS_CONVERTED_SHARES);
        vm.stopPrank();

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + SUSDS_CONVERTED_SHARES);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        // Max available with rounding
        vm.prank(relayer);
        uint256 shares = mainnetController.withdrawERC4626(
            address(susds),
            1e18 - 1,
            SUSDS_CONVERTED_SHARES
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(shares, SUSDS_CONVERTED_SHARES);

        assertEq(usds.balanceOf(address(almProxy)),          1e18 - 1);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1);  // Rounding

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);
    }

}

contract MainnetControllerRedeemERC4626FailureTests is SUSDSTestBase {

    function test_redeemERC4626_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.redeemERC4626(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.redeemERC4626(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_zeroMaxAmount() external {
        // Longer setup because rate limit revert is at the end of the function
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(
                mainnetController.LIMIT_4626_WITHDRAW(),
                Ethereum.SUSDS
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.startPrank(relayer);
        mainnetController.mintUSDS(100e18);
        mainnetController.depositERC4626(address(susds), 100e18, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.redeemERC4626(address(susds), 1e18, 1e18);
    }

    function test_redeemERC4626_rateLimitBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 10_000_000e18, uint256(1_000_000e18) / 4 hours);
        vm.stopPrank();

        vm.startPrank(relayer);

        mainnetController.mintUSDS(10_000_000e18);
        mainnetController.depositERC4626(address(susds), 10_000_000e18, 0);

        uint256 overBoundaryShares = susds.convertToShares(5_000_000e18 + 2);
        uint256 atBoundaryShares   = susds.convertToShares(5_000_000e18 + 1);  // Still rounds down

        assertEq(susds.previewRedeem(overBoundaryShares), 5_000_000e18 + 1);
        assertEq(susds.previewRedeem(atBoundaryShares),   5_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.redeemERC4626(address(susds), overBoundaryShares, 1e18);

        mainnetController.redeemERC4626(address(susds), atBoundaryShares, 1e18);

        vm.stopPrank();
    }

    function test_redeemERC4626_minAssetsOutNotMet() external {
        vm.startPrank(relayer);
        mainnetController.mintUSDS(2e18);
        mainnetController.depositERC4626(address(susds), 2e18, 0);

        vm.expectRevert("MC/min-assets-out-not-met");
        mainnetController.redeemERC4626(address(susds), 1e18, 2e18);
        vm.stopPrank();
    }

    function test_redeemERC4626_minAssetsOutNotMetBoundary() external {
        vm.startPrank(relayer);

        mainnetController.mintUSDS(2_000_000e18);
        mainnetController.depositERC4626(address(susds), 2_000_000e18, 0);

        uint256 shares = susds.convertToShares(2_000_000e18);

        uint256 overBoundaryAssets = susds.convertToAssets(shares) + 1;
        uint256 atBoundaryAssets   = susds.convertToAssets(shares);

        vm.expectRevert("MC/min-assets-out-not-met");
        mainnetController.redeemERC4626(address(susds), shares, overBoundaryAssets);

        mainnetController.redeemERC4626(address(susds), shares, atBoundaryAssets);
        vm.stopPrank();
    }

}

contract MainnetControllerRedeemERC4626Tests is SUSDSTestBase {

    function test_redeemERC4626() external {
        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_4626_DEPOSIT(),
            Ethereum.SUSDS
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_4626_WITHDRAW(),
            Ethereum.SUSDS
        );

        vm.startPrank(relayer);
        mainnetController.mintUSDS(1e18);
        mainnetController.depositERC4626(address(susds), 1e18, SUSDS_CONVERTED_SHARES);
        vm.stopPrank();

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1e18);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)),  0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY + SUSDS_CONVERTED_SHARES);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS + 1e18);
        assertEq(susds.balanceOf(address(almProxy)), SUSDS_CONVERTED_SHARES);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18);

        vm.record();

        vm.prank(relayer);
        uint256 assets = mainnetController.redeemERC4626(
            address(susds),
            SUSDS_CONVERTED_SHARES,
            1e18 - 1 // Rounding
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  4_999_999e18 + (1e18 - 1));
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), 5_000_000e18 - (1e18 - 1));

        assertEq(assets, 1e18 - 1);  // Rounding

        assertEq(usds.balanceOf(address(almProxy)),          1e18 - 1);  // Rounding
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.balanceOf(address(susds)),             USDS_BAL_SUSDS + SUSDS_DRIP_AMOUNT + 1);  // Rounding

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), address(susds)), 0);

        assertEq(susds.totalSupply(),                SUSDS_TOTAL_SUPPLY);
        assertEq(susds.totalAssets(),                SUSDS_TOTAL_ASSETS);
        assertEq(susds.balanceOf(address(almProxy)), 0);
    }

}
