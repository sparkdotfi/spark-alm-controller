// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract ForeignControllerPSMSuccessTestBase is ForkTestBase {

    function _assertState(
        IERC20  token,
        uint256 proxyBalance,
        uint256 psmBalance,
        uint256 proxyShares,
        uint256 totalShares,
        uint256 totalAssets,
        bytes32 rateLimitKey,
        uint256 currentRateLimit
    )
        internal view
    {
        address custodian = address(token) == address(usdcBase) ? pocket : address(psmBase);

        assertEq(token.balanceOf(address(almProxy)),          proxyBalance);
        assertEq(token.balanceOf(address(foreignController)), 0);  // Should always be zero
        assertEq(token.balanceOf(custodian),                  psmBalance);

        assertEq(psmBase.shares(address(almProxy)), proxyShares);
        assertEq(psmBase.totalShares(),             totalShares);
        assertEq(psmBase.totalAssets(),             totalAssets);

        bytes32 assetKey = RateLimitHelpers.makeAddressKey(rateLimitKey, address(token));

        assertEq(rateLimits.getCurrentRateLimit(assetKey), currentRateLimit);

        // Should always be 0 before and after calls
        assertEq(usdsBase.allowance(address(almProxy), address(psmBase)), 0);
    }

}


contract ForeignControllerDepositPSMFailureTests is ForkTestBase {

    function test_depositPSM_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.depositPSM(address(usdsBase), 1_000_000e18);
    }

    function test_depositPSM_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.depositPSM(makeAddr("fake-token"), 1_000_000e18);
    }

    function test_depositPSM_usdcRateLimitedBoundary() external {
        deal(address(usdcBase), address(almProxy), 5_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositPSM(address(usdcBase), 5_000_000e6 + 1);

        foreignController.depositPSM(address(usdcBase), 5_000_000e6);
    }

    function test_depositPSM_usdsRateLimitedBoundary() external {
        deal(address(usdsBase), address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositPSM(address(usdsBase), 5_000_000e18 + 1);

        foreignController.depositPSM(address(usdsBase), 5_000_000e18);
    }

    function test_depositPSM_susdsRateLimitedBoundary() external {
        deal(address(susdsBase), address(almProxy), 5_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositPSM(address(susdsBase), 5_000_000e18 + 1);

        foreignController.depositPSM(address(susdsBase), 5_000_000e18);
    }

}

contract ForeignControllerDepositPSMTests is ForeignControllerPSMSuccessTestBase {

    function test_depositPSM_depositUsds() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(address(usdsBase), address(almProxy), 100e18);

        _assertState({
            token            : usdsBase,
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.prank(relayer);
        uint256 shares = foreignController.depositPSM(address(usdsBase), 100e18);

        assertEq(shares, 100e18);

        _assertState({
            token            : usdsBase,
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

    function test_depositPSM_depositUsdc() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(address(usdcBase), address(almProxy), 100e6);

        _assertState({
            token            : usdcBase,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.prank(relayer);
        uint256 shares = foreignController.depositPSM(address(usdcBase), 100e6);

        assertEq(shares, 100e18);

        _assertState({
            token            : usdcBase,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_depositPSM_depositSUsds() external {
        bytes32 key = foreignController.LIMIT_PSM_DEPOSIT();

        deal(address(susdsBase), address(almProxy), 100e18);

        _assertState({
            token            : susdsBase,
            proxyBalance     : 100e18,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e18
        });

        vm.prank(relayer);
        uint256 shares = foreignController.depositPSM(address(susdsBase), 100e18);

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : susdsBase,
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e18
        });
    }

}

contract ForeignControllerWithdrawPSMFailureTests is ForkTestBase {

    function test_withdrawPSM_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.withdrawPSM(address(usdsBase), 100e18);
    }

    function test_withdrawPSM_usdcZeroMaxAmount() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(usdcBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.withdrawPSM(address(usdcBase), 100e18);
    }

    function test_withdrawPSM_usdsZeroMaxAmount() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(usdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.withdrawPSM(address(usdsBase), 100e18);
    }

    function test_withdrawPSM_susdsZeroMaxAmount() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(susdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        foreignController.withdrawPSM(address(susdsBase), 100e18);
    }

    function test_withdrawPSM_usdcRateLimitedBoundary() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(usdcBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        deal(address(usdcBase), address(almProxy), 1_000_000e6 + 1);

        vm.startPrank(relayer);
        foreignController.depositPSM(address(usdcBase), 1_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(usdcBase), 1_000_000e6 + 1);

        foreignController.withdrawPSM(address(usdcBase), 1_000_000e6);
    }

    function test_withdrawPSM_usdsRateLimitedBoundary() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(usdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        deal(address(usdsBase), address(almProxy), 1_000_000e18 + 1);

        vm.startPrank(relayer);
        foreignController.depositPSM(address(usdsBase), 1_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(usdsBase), 1_000_000e18 + 1);

        foreignController.withdrawPSM(address(usdsBase), 1_000_000e18);
    }

    function test_withdrawPSM_susdsRateLimitedBoundary() external {
        bytes32 withdrawKey      = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 withdrawAssetKey = RateLimitHelpers.makeAddressKey(withdrawKey, address(susdsBase));

        vm.prank(SPARK_EXECUTOR);
        rateLimits.setRateLimitData(withdrawAssetKey, 1_000_000e18, uint256(1_000_000e18) / 1 days);

        // NOTE: Need an extra wei because of rounding on conversion
        deal(address(susdsBase), address(almProxy), 1_000_000e18 + 2);

        vm.startPrank(relayer);
        foreignController.depositPSM(address(susdsBase), 1_000_000e18 + 2);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.withdrawPSM(address(susdsBase), 1_000_000e18 + 1);

        uint256 withdrawn = foreignController.withdrawPSM(address(susdsBase), 1_000_000e18);

        assertEq(withdrawn, 1_000_000e18);
    }

}

contract ForeignControllerWithdrawPSMTests is ForeignControllerPSMSuccessTestBase {

    function test_withdrawPSM_withdrawUsds() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(address(usdsBase), address(almProxy), 100e18);
        vm.prank(relayer);
        foreignController.depositPSM(address(usdsBase), 100e18);

        _assertState({
            token            : usdsBase,
            proxyBalance     : 0,
            psmBalance       : 101e18,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.prank(relayer);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(usdsBase), 100e18);

        assertEq(amountWithdrawn, 100e18);

        _assertState({
            token            : usdsBase,
            proxyBalance     : 100e18,
            psmBalance       : 1e18,  // From seeding USDS
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

    function test_withdrawPSM_withdrawUsdc() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(address(usdcBase), address(almProxy), 100e6);
        vm.prank(relayer);
        foreignController.depositPSM(address(usdcBase), 100e6);

        _assertState({
            token            : usdcBase,
            proxyBalance     : 0,
            psmBalance       : 100e6,
            proxyShares      : 100e18,
            totalShares      : 101e18,
            totalAssets      : 101e18,
            rateLimitKey     : key,
            currentRateLimit : 5_000_000e6
        });

        vm.prank(relayer);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(usdcBase), 100e6);

        assertEq(amountWithdrawn, 100e6);

        _assertState({
            token            : usdcBase,
            proxyBalance     : 100e6,
            psmBalance       : 0,
            proxyShares      : 0,
            totalShares      : 1e18,  // From seeding USDS
            totalAssets      : 1e18,  // From seeding USDS
            rateLimitKey     : key,
            currentRateLimit : 4_999_900e6
        });
    }

    function test_withdrawPSM_withdrawSUsds() external {
        bytes32 key = foreignController.LIMIT_PSM_WITHDRAW();

        deal(address(susdsBase), address(almProxy), 100e18);
        vm.prank(relayer);
        uint256 shares = foreignController.depositPSM(address(susdsBase), 100e18);

        assertEq(shares, 100.343092065533568746e18);  // Sanity check conversion at fork block

        _assertState({
            token            : susdsBase,
            proxyBalance     : 0,
            psmBalance       : 100e18,
            proxyShares      : shares,
            totalShares      : 1e18 + shares,
            totalAssets      : 1e18 + shares,
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });

        vm.prank(relayer);
        uint256 amountWithdrawn = foreignController.withdrawPSM(address(susdsBase), 100e18);

        assertEq(amountWithdrawn, 100e18 - 1);  // Rounding

        _assertState({
            token            : susdsBase,
            proxyBalance     : 100e18 - 1,  // Rounding
            psmBalance       : 1,           // Rounding
            proxyShares      : 0,
            totalShares      : 1e18,      // From seeding USDS
            totalAssets      : 1e18 + 1,  // From seeding USDS, rounding
            rateLimitKey     : key,
            currentRateLimit : type(uint256).max
        });
    }

}
