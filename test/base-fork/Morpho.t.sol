// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id }       from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract MorphoBaseTest is ForkTestBase {

    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address constant MORPHO_VAULT_USDS = 0x0fFDeCe791C5a2cb947F8ddBab489E5C02c6d4F7;
    address constant MORPHO_VAULT_USDC = 0x305E03Ed9ADaAB22F4A58c24515D79f2B1E2FD5D;

    IERC4626 usdsVault = IERC4626(MORPHO_VAULT_USDS);
    IERC4626 usdcVault = IERC4626(MORPHO_VAULT_USDC);

    function setUp() public override {
        super.setUp();

        vm.startPrank(Base.SPARK_EXECUTOR);

        // Add in the idle markets so deposits can be made
        MarketParams memory usdsParams = MarketParams({
            loanToken:       Base.USDS,
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            0
        });
        MarketParams memory usdcParams = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            0
        });
        IMorpho(MORPHO).createMarket(
            usdsParams
        );
        // USDC idle market already exists
        IMetaMorpho(MORPHO_VAULT_USDS).submitCap(
            usdsParams,
            type(uint184).max
        );
        IMetaMorpho(MORPHO_VAULT_USDC).submitCap(
            usdcParams,
            type(uint184).max
        );

        skip(1 days);

        IMetaMorpho(MORPHO_VAULT_USDS).acceptCap(usdsParams);
        IMetaMorpho(MORPHO_VAULT_USDC).acceptCap(usdcParams);

        Id[] memory supplyQueueUSDS = new Id[](1);
        supplyQueueUSDS[0] = MarketParamsLib.id(usdsParams);
        IMetaMorpho(MORPHO_VAULT_USDS).setSupplyQueue(supplyQueueUSDS);
        Id[] memory supplyQueueUSDC = new Id[](1);
        supplyQueueUSDC[0] = MarketParamsLib.id(usdcParams);
        IMetaMorpho(MORPHO_VAULT_USDC).setSupplyQueue(supplyQueueUSDC);

        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                MORPHO_VAULT_USDS
            ),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                MORPHO_VAULT_USDC
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22841965;  // November 24, 2024
    }

}

// NOTE: Only testing USDS for non-rate limit failures as it doesn't matter which asset is used

contract MorphoDepositFailureTests is MorphoBaseTest {

    function test_morpho_deposit_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

    function test_morpho_deposit_frozen() external {
        vm.prank(freezer);
        foreignController.freeze();

        vm.prank(relayer);
        vm.expectRevert("ForeignController/not-active");
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

    function test_morpho_usds_deposit_rateLimitedBoundary() external {
        deal(Base.USDS, address(almProxy), 25_000_000e18 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18 + 1);

        foreignController.depositERC4626(MORPHO_VAULT_USDS, 25_000_000e18);
    }

    function test_morpho_usdc_deposit_rateLimitedBoundary() external {
        deal(Base.USDC, address(almProxy), 25_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.startPrank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 25_000_000e6 + 1);

        foreignController.depositERC4626(MORPHO_VAULT_USDC, 25_000_000e6);
    }

}

contract MorphoDepositSuccessTests is MorphoBaseTest {

    function test_morpho_usds_deposit() public {
        deal(Base.USDS, address(almProxy), 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))),          0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                             1_000_000e18);
        assertEq(IERC20(Base.USDS).allowance(address(almProxy), address(MORPHO_VAULT_USDS)), 0);

        vm.prank(relayer);
        assertEq(foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18), 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))),          1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                             0);
        assertEq(IERC20(Base.USDS).allowance(address(almProxy), address(MORPHO_VAULT_USDS)), 0);
    }

    function test_morpho_usdc_deposit() public {
        deal(Base.USDC, address(almProxy), 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))),          0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                             1_000_000e6);
        assertEq(IERC20(Base.USDC).allowance(address(almProxy), address(MORPHO_VAULT_USDC)), 0);

        vm.prank(relayer);
        assertEq(foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6), 1_000_000e18);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))),          1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                             0);
        assertEq(IERC20(Base.USDC).allowance(address(almProxy), address(MORPHO_VAULT_USDC)), 0);
    }

}

contract MorphoWithdrawFailureTests is MorphoBaseTest {

    function test_morpho_withdraw_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

    function test_morpho_withdraw_frozen() external {
        vm.prank(freezer);
        foreignController.freeze();

        vm.prank(relayer);
        vm.expectRevert("ForeignController/not-active");
        foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

}

contract MorphoWithdrawSuccessTests is MorphoBaseTest {

    function test_morpho_usds_withdraw() public {
        deal(Base.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    0);

        vm.prank(relayer);
        assertEq(foreignController.withdrawERC4626(MORPHO_VAULT_USDS, 1_000_000e18), 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    1_000_000e18);
    }

    function test_morpho_usdc_withdraw() public {
        deal(Base.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    0);

        vm.prank(relayer);
        assertEq(foreignController.withdrawERC4626(MORPHO_VAULT_USDC, 1_000_000e6), 1_000_000e18);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    1_000_000e6);
    }

}

contract MorphoRedeemFailureTests is MorphoBaseTest {

    function test_morpho_redeem_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

    function test_morpho_redeem_frozen() external {
        vm.prank(freezer);
        foreignController.freeze();

        vm.prank(relayer);
        vm.expectRevert("ForeignController/not-active");
        foreignController.redeemERC4626(MORPHO_VAULT_USDS, 1_000_000e18);
    }

}

contract MorphoRedeemSuccessTests is MorphoBaseTest {

    function test_morpho_usds_redeem() public {
        deal(Base.USDS, address(almProxy), 1_000_000e18);
        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDS, 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 1_000_000e18);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    0);

        uint256 shares = usdsVault.balanceOf(address(almProxy));
        vm.prank(relayer);
        assertEq(foreignController.redeemERC4626(MORPHO_VAULT_USDS, shares), 1_000_000e18);

        assertEq(usdsVault.convertToAssets(usdsVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDS).balanceOf(address(almProxy)),                    1_000_000e18);
    }

    function test_morpho_usdc_redeem() public {
        deal(Base.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        foreignController.depositERC4626(MORPHO_VAULT_USDC, 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 1_000_000e6);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    0);

        uint256 shares = usdcVault.balanceOf(address(almProxy));
        vm.prank(relayer);
        assertEq(foreignController.redeemERC4626(MORPHO_VAULT_USDC, shares), 1_000_000e6);

        assertEq(usdcVault.convertToAssets(usdcVault.balanceOf(address(almProxy))), 0);
        assertEq(IERC20(Base.USDC).balanceOf(address(almProxy)),                    1_000_000e6);
    }

}
