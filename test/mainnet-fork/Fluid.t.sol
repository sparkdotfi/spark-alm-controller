// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./ForkTestBase.t.sol";
import {IFluidSmartLending} from "../../src/libraries/FluidLib.sol";

contract FluidTestBase is ForkTestBase {
    address constant SMART_LENDING_SUSDS_USDT =
        0x7cA3814E21E96758d27e4e07B8d021DE70fC4Db6;

    address constant DEX_SUSDS_USDT =
        0xF507a38Aaf37339cC3bEAc4C7a58B17401BDf6bc;

    bytes32 DEPOSIT_KEY_TOKEN0;
    bytes32 DEPOSIT_KEY_TOKEN1;
    bytes32 WITHDRAW_KEY;

    function setUp() public override {
        super.setUp();

        vm.label(SMART_LENDING_SUSDS_USDT, "smart-lending-susds-usdt");
        vm.label(DEX_SUSDS_USDT, "dex-susds-usdt");

        assertEq(
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).TOKEN0(),
            address(susds)
        );
        assertEq(
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).TOKEN1(),
            address(usdt)
        );

        DEPOSIT_KEY_TOKEN0 = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_FLUID_SL_DEPOSIT(),
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).TOKEN0(), // SUSDS
            SMART_LENDING_SUSDS_USDT
        );
        DEPOSIT_KEY_TOKEN1 = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_FLUID_SL_DEPOSIT(),
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).TOKEN1(), // USDT
            SMART_LENDING_SUSDS_USDT
        );

        WITHDRAW_KEY = RateLimitHelpers.makeAssetKey(
            mainnetController.LIMIT_FLUID_SL_WITHDRAW(),
            SMART_LENDING_SUSDS_USDT
        );

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            DEPOSIT_KEY_TOKEN0,
            10_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );
        rateLimits.setRateLimitData(
            DEPOSIT_KEY_TOKEN1,
            5_000_000e6,
            uint256(1_000_000e6) / 4 hours
        );
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            7_700_000e18,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal pure virtual override returns (uint256) {
        return 22511418; //  May 18, 2025
    }

    function _runDepositTest(
        uint256 depositSUSDS,
        uint256 depositUSDT,
        uint256 allowedSlippage
    ) internal returns (uint256 minShares, uint256 shares) {
        // max ever expected shares:
        // susds deposit amount in USDS
        // USDT deposit amount scaled to 1e18
        // for common ~USD value
        // / 2 because 1 share = ~2$
        uint256 maxExpectedShares = ((susds.convertToAssets(depositSUSDS) +
            depositUSDT *
            1e12) / 2);

        // min shares:
        // max shares adjusted for allowed slippage 0.3%
        minShares = (maxExpectedShares * (1e18 - allowedSlippage)) / 1e18;

        deal(address(usdt), address(almProxy), depositUSDT);
        deal(address(susds), address(almProxy), depositSUSDS);

        assertEq(
            susds.allowance(address(almProxy), SMART_LENDING_SUSDS_USDT),
            0
        );
        assertEq(
            usdt.allowance(address(almProxy), SMART_LENDING_SUSDS_USDT),
            0
        );

        assertEq(susds.balanceOf(address(almProxy)), depositSUSDS);
        assertEq(usdt.balanceOf(address(almProxy)), depositUSDT);

        assertEq(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0
        );

        vm.prank(relayer);
        shares = mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            depositSUSDS,
            depositUSDT,
            minShares
        );

        assertApproxEqRel(shares, maxExpectedShares, allowedSlippage);

        assertEq(
            susds.allowance(address(almProxy), SMART_LENDING_SUSDS_USDT),
            0
        );
        assertEq(
            usdt.allowance(address(almProxy), SMART_LENDING_SUSDS_USDT),
            0
        );
        assertEq(susds.balanceOf(address(almProxy)), 0);
        assertEq(usdt.balanceOf(address(almProxy)), 0);

        assertApproxEqAbs(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            shares, // 1 share =~ 1 token (ignore rounding)
            1
        );
    }
}

contract MainnetControllerDepositFluidSmartLendingFailureTests is
    FluidTestBase
{
    function test_depositFluidSmartLending_notRelayer() external {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                RELAYER
            )
        );
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            1e18,
            1e17
        );
    }

    function test_depositFluidSmartLending_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(DEPOSIT_KEY_TOKEN1, 0, uint256(0));
        rateLimits.setRateLimitData(DEPOSIT_KEY_TOKEN1, 0, uint256(0));
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            1e18,
            1e17
        );
    }

    function test_depositFluidSmartLending_zeroMaxAmountToken0() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(DEPOSIT_KEY_TOKEN0, 0, uint256(0));
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            1e18,
            1e17
        );
    }

    function test_depositFluidSmartLending_zeroMaxAmountToken1() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(DEPOSIT_KEY_TOKEN1, 0, uint256(0));
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            1e18,
            1e17
        );
    }

    function test_depositFluidSmartLending_rateLimitBoundaryToken0() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            10_000_000e18 + 1,
            1e18,
            1e17
        );

        vm.stopPrank();
    }

    function test_depositFluidSmartLending_rateLimitBoundaryToken1() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.depositFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            2_000_000e18,
            5_000_000e6 + 1,
            1e17
        );

        vm.stopPrank();
    }
}

contract MainnetControllerDepositFluidSmartLendingTests is FluidTestBase {
    function test_depositFluidSmartLending() external {
        uint256 depositSUSDS = 10_000_000e18;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3e15; // 0.3%

        assertEq(
            rateLimits.getCurrentRateLimit(DEPOSIT_KEY_TOKEN0),
            depositSUSDS
        );
        assertEq(
            rateLimits.getCurrentRateLimit(DEPOSIT_KEY_TOKEN1),
            depositUSDT
        );

        (uint256 minShares, uint256 shares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        assertEq(minShares, 7736135739495555912394546);
        assertEq(shares, 7737242887687624616258883);
    }

    function test_depositFluidSmartLendingToken0() external {
        uint256 depositSUSDS = 10_000_000e18;
        uint256 depositUSDT = 0;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (uint256 minShares, uint256 shares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        assertEq(minShares, 52410060_32504835974625040);
        assertEq(shares, 5242170_890048746293680135);
    }

    function test_depositFluidSmartLendingToken1() external {
        uint256 depositSUSDS = 0;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (uint256 minShares, uint256 shares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        assertEq(minShares, 2491250_000000000000000000);
        assertEq(shares, 2491857_761117607089110190);
    }
}

contract MainnetControllerWithdrawFluidSmartLendingFailureTests is
    FluidTestBase
{
    function test_withdrawFluidSmartLending_notRelayer() external {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                RELAYER
            )
        );
        mainnetController.withdrawFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            1e18,
            1e30
        );
    }

    function test_withdrawFluidSmartLending_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawFluidSmartLending(
            makeAddr("fake-token"),
            1e18,
            1e18,
            1e30
        );
    }

    function test_withdrawFluidSmartLending_rateLimitBoundaryToken1() external {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            10_000_000e18 + 1,
            5_000_000e6 + 1,
            1e30
        );

        vm.stopPrank();
    }
}

contract MainnetControllerWithdrawFluidSmartLendingTests is FluidTestBase {
    function test_withdrawFluidSmartLending() external {
        uint256 depositSUSDS = 10_000_000e18;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3e15; // 0.3%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw in chunks according to withdraw limit at Fluid side (max 25% at once, after < 8M$ all at once possible)
        uint256 withdrawnShares;
        uint256 withdrawnUSDT;
        uint256 withdrawnSUSDS;

        {
            // 15M to 11.4M
            vm.prank(relayer);
            withdrawnSUSDS = (depositSUSDS * 24) / 100;
            withdrawnUSDT = (depositUSDT * 24) / 100;

            withdrawnShares = mainnetController.withdrawFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                withdrawnSUSDS,
                withdrawnUSDT,
                maxWithdrawSharesSlippage
            );
        }

        {
            // 11.4M to 8.66M
            vm.warp(block.timestamp + 12 hours);
            vm.prank(relayer);
            uint256 withdrawSUSDS = ((depositSUSDS - withdrawnSUSDS) * 24) /
                100;
            withdrawnSUSDS += withdrawSUSDS;
            uint256 withdrawUSDT = ((depositUSDT - withdrawnUSDT) * 24) / 100;
            withdrawnUSDT += withdrawUSDT;

            withdrawnShares += mainnetController.withdrawFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                withdrawSUSDS,
                withdrawUSDT,
                maxWithdrawSharesSlippage - withdrawnShares
            );
        }

        {
            // 8.66M to 6.585M
            vm.warp(block.timestamp + 12 hours);
            vm.prank(relayer);
            uint256 withdrawSUSDS = ((depositSUSDS - withdrawnSUSDS) * 24) /
                100;
            withdrawnSUSDS += withdrawSUSDS;
            uint256 withdrawUSDT = ((depositUSDT - withdrawnUSDT) * 24) / 100;
            withdrawnUSDT += withdrawUSDT;

            withdrawnShares += mainnetController.withdrawFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                withdrawSUSDS,
                withdrawUSDT,
                maxWithdrawSharesSlippage - withdrawnShares
            );
        }

        {
            // 6.585M fully down to ~0
            vm.prank(relayer);
            uint256 withdrawSUSDS = depositSUSDS - withdrawnSUSDS;
            withdrawnSUSDS += withdrawSUSDS;
            uint256 withdrawUSDT = depositUSDT - withdrawnUSDT;
            withdrawnUSDT += withdrawUSDT;

            withdrawnShares += mainnetController.withdrawFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                (withdrawSUSDS * 9999) / 10000,
                (withdrawUSDT * 9999) / 10000,
                maxWithdrawSharesSlippage - withdrawnShares
            );
        }

        assertApproxEqRel(depositedShares, withdrawnShares, 1e14); // 0.01% dust leftover allowed
        assertEq(withdrawnSUSDS, depositSUSDS);
        assertEq(withdrawnUSDT, depositUSDT);

        assertApproxEqRel(
            susds.balanceOf(address(almProxy)),
            depositSUSDS,
            1e14
        ); // 0.01% slippage allowed
        assertApproxEqRel(usdt.balanceOf(address(almProxy)), depositUSDT, 1e14); // 0.01% slippage allowed

        assertApproxEqAbs(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0,
            5e20 // ~1k $ leftover in shares
        );
    }

    function test_withdrawFluidSmartLendingToken0() external {
        uint256 depositSUSDS = 5_000_000e18;
        uint256 depositUSDT = 0;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw all at once

        vm.prank(relayer);
        uint256 withdrawnShares = mainnetController.withdrawFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            (depositSUSDS * 9999) / 10000,
            (depositUSDT * 9999) / 10000,
            maxWithdrawSharesSlippage
        );

        assertApproxEqRel(depositedShares, withdrawnShares, 1e14); // 0.01% dust leftover allowed

        assertApproxEqRel(
            susds.balanceOf(address(almProxy)),
            depositSUSDS,
            1e14
        ); // 0.01% slippage allowed
        assertApproxEqRel(usdt.balanceOf(address(almProxy)), depositUSDT, 1e14); // 0.01% slippage allowed

        assertApproxEqAbs(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0,
            1e20 // ~200 $ leftover in shares
        );
    }

    function test_withdrawFluidSmartLendingToken1() external {
        uint256 depositSUSDS = 0;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw all at once
        vm.prank(relayer);
        uint256 withdrawnShares = mainnetController.withdrawFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            (depositSUSDS * 9999) / 10000,
            (depositUSDT * 9999) / 10000,
            maxWithdrawSharesSlippage
        );

        assertApproxEqRel(depositedShares, withdrawnShares, 1e14); // 0.01% dust leftover allowed

        assertApproxEqRel(
            susds.balanceOf(address(almProxy)),
            depositSUSDS,
            1e14
        ); // 0.01% slippage allowed
        assertApproxEqRel(usdt.balanceOf(address(almProxy)), depositUSDT, 1e14); // 0.01% slippage allowed

        assertApproxEqAbs(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0,
            1e20 // ~200 $ leftover in shares
        );
    }
}

contract MainnetControllerWithdrawPerfectFluidSmartLendingFailureTests is
    FluidTestBase
{
    function test_withdrawPerfectFluidSmartLending_notRelayer() external {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                RELAYER
            )
        );
        mainnetController.withdrawPerfectFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            1e18,
            10,
            10
        );
    }

    function test_withdrawPerfectFluidSmartLending_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.withdrawPerfectFluidSmartLending(
            makeAddr("fake-token"),
            1e18,
            10,
            10
        );
    }

    function test_withdrawPerfectFluidSmartLending_rateLimitBoundaryToken1()
        external
    {
        vm.startPrank(relayer);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.withdrawPerfectFluidSmartLending(
            SMART_LENDING_SUSDS_USDT,
            7_700_000e18 + 1,
            10,
            10
        );

        vm.stopPrank();
    }
}

contract MainnetControllerWithdrawPerfectFluidSmartLendingTests is
    FluidTestBase
{
    function test_withdrawPerfectFluidSmartLending() external {
        {
            // add some initial deposit balance to the smart lending
            address bob = makeAddr("bob");
            deal(address(susds), address(bob), 100_000e18);
            vm.startPrank(bob);
            susds.approve(SMART_LENDING_SUSDS_USDT, 100_000e18);
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).deposit(
                100_000e18,
                0,
                1,
                bob
            );
            vm.stopPrank();
        }

        uint256 depositSUSDS = 10_000_000e18;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3e15; // 0.3%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw in chunks according to withdraw limit at Fluid side (max 25% at once, after < 8M$ all at once possible)
        uint256 withdrawnShares;

        {
            // 15M to 11.4M
            vm.prank(relayer);
            uint256 withdrawShares = (depositedShares * 24) / 100;

            withdrawnShares = mainnetController
                .withdrawPerfectFluidSmartLending(
                    SMART_LENDING_SUSDS_USDT,
                    withdrawShares,
                    10,
                    10
                );
        }

        {
            // 11.4M to 8.66M
            vm.warp(block.timestamp + 12 hours);
            vm.prank(relayer);
            uint256 withdrawShares = ((depositedShares - withdrawnShares) *
                24) / 100;

            withdrawnShares += mainnetController
                .withdrawPerfectFluidSmartLending(
                    SMART_LENDING_SUSDS_USDT,
                    withdrawShares,
                    10,
                    10
                );
        }

        {
            // 8.66M to 6.585M
            vm.warp(block.timestamp + 12 hours);
            vm.prank(relayer);
            uint256 withdrawShares = ((depositedShares - withdrawnShares) *
                24) / 100;

            withdrawnShares += mainnetController
                .withdrawPerfectFluidSmartLending(
                    SMART_LENDING_SUSDS_USDT,
                    withdrawShares,
                    10,
                    10
                );
        }

        {
            // 6.585M fully down to ~0
            vm.prank(relayer);
            withdrawnShares += mainnetController
                .withdrawPerfectFluidSmartLending(
                    SMART_LENDING_SUSDS_USDT,
                    type(uint256).max, // withdraw max
                    10,
                    10
                );
        }

        assertApproxEqAbs(depositedShares, withdrawnShares, 1); // no leftover allowed, ignore rounding
        assertEq(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0
        );

        uint256 expectedCombinedBalanceUSDT = susds.convertToAssets(
            depositSUSDS
        ) + depositUSDT * 1e12;

        uint256 balanceCombinedUSDT = susds.convertToAssets(
            susds.balanceOf(address(almProxy))
        ) + usdt.balanceOf(address(almProxy)) * 1e12;

        assertApproxEqRel(
            expectedCombinedBalanceUSDT,
            balanceCombinedUSDT,
            2e13
        ); // 0.002% slippage allowed
    }

    function test_withdrawPerfectFluidSmartLendingToken0() external {
        {
            // add some initial deposit balance to the smart lending
            address bob = makeAddr("bob");
            deal(address(susds), address(bob), 100_000e18);
            vm.startPrank(bob);
            susds.approve(SMART_LENDING_SUSDS_USDT, 100_000e18);
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).deposit(
                100_000e18,
                0,
                1,
                bob
            );
            vm.stopPrank();
        }

        uint256 depositSUSDS = 5_000_000e18;
        uint256 depositUSDT = 0;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw all at once in token 0 only
        vm.prank(relayer);
        uint256 withdrawnShares = mainnetController
            .withdrawPerfectFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                type(uint256).max, // withdraw max
                10,
                0 // 0 token1
            );

        assertApproxEqAbs(depositedShares, withdrawnShares, 1); // no leftover allowed, ignore rounding
        assertEq(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0
        );

        uint256 expectedCombinedBalanceUSDT = susds.convertToAssets(
            depositSUSDS
        ) + depositUSDT * 1e12;

        uint256 balanceCombinedUSDT = susds.convertToAssets(
            susds.balanceOf(address(almProxy))
        ) + usdt.balanceOf(address(almProxy)) * 1e12;

        assertApproxEqRel(
            expectedCombinedBalanceUSDT,
            balanceCombinedUSDT,
            1.1e14
        ); // 0.011% slippage allowed
    }

    function test_withdrawPerfectFluidSmartLendingToken1() external {
        {
            // add some initial deposit balance to the smart lending
            address bob = makeAddr("bob");
            deal(address(susds), address(bob), 100_000e18);
            vm.startPrank(bob);
            susds.approve(SMART_LENDING_SUSDS_USDT, 100_000e18);
            IFluidSmartLending(SMART_LENDING_SUSDS_USDT).deposit(
                100_000e18,
                0,
                1,
                bob
            );
            vm.stopPrank();
        }

        uint256 depositSUSDS = 0;
        uint256 depositUSDT = 5_000_000e6;
        uint256 allowedSlippage = 3.5e15; // 0.35%

        (, uint256 depositedShares) = _runDepositTest(
            depositSUSDS,
            depositUSDT,
            allowedSlippage
        );

        uint256 maxWithdrawSharesSlippage = (depositedShares * (1e18 + 1e15)) /
            1e18;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            WITHDRAW_KEY,
            maxWithdrawSharesSlippage,
            uint256(1_000_000e18) / 4 hours
        );
        vm.stopPrank();

        // withdraw all at once in token 1 only
        vm.prank(relayer);
        uint256 withdrawnShares = mainnetController
            .withdrawPerfectFluidSmartLending(
                SMART_LENDING_SUSDS_USDT,
                type(uint256).max, // withdraw max
                0, // 0 token0
                10
            );

        assertApproxEqAbs(depositedShares, withdrawnShares, 1); // no leftover allowed, ignore rounding
        assertEq(
            IERC20(SMART_LENDING_SUSDS_USDT).balanceOf(address(almProxy)),
            0
        );

        uint256 expectedCombinedBalanceUSDT = susds.convertToAssets(
            depositSUSDS
        ) + depositUSDT * 1e12;

        uint256 balanceCombinedUSDT = susds.convertToAssets(
            susds.balanceOf(address(almProxy))
        ) + usdt.balanceOf(address(almProxy)) * 1e12;

        assertApproxEqRel(
            expectedCombinedBalanceUSDT,
            balanceCombinedUSDT,
            1.1e14
        ); // 0.011% slippage allowed
    }
}
