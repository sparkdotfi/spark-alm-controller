// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id, MarketAllocation } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract MorphoTestBase is ForkTestBase {

    address internal constant PT_SUSDE_27MAR2025_PRICE_FEED = 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7;
    address internal constant PT_SUSDE_27MAR2025            = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;

    IMetaMorpho morphoVault = IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1);
    IMorpho     morpho      = IMorpho(Ethereum.MORPHO);

    // Using March and May 2025 sUSDe PT markets for testing
    MarketParams market1 = MarketParams({
        loanToken       : Ethereum.DAI,
        collateralToken : PT_SUSDE_27MAR2025,
        oracle          : PT_SUSDE_27MAR2025_PRICE_FEED,
        irm             : Ethereum.MORPHO_DEFAULT_IRM,
        lltv            : 0.915e18
    });
    MarketParams market2 = MarketParams({
        loanToken       : Ethereum.DAI,
        collateralToken : PT_SUSDE_29MAY2025,
        oracle          : PT_SUSDE_29MAY2025_PRICE_FEED,
        irm             : Ethereum.MORPHO_DEFAULT_IRM,
        lltv            : 0.915e18
    });

    function setUp() public override {
        super.setUp();

        // Spell onboarding (Ability to deposit necessary to onboard a vault for allocations)
        vm.startPrank(Ethereum.SPARK_PROXY);
        morphoVault.setIsAllocator(address(almProxy), true);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21680000;  // Jan 22, 2024
    }

    function positionShares(MarketParams memory marketParams) internal view returns (uint256) {
        return morpho.position(MarketParamsLib.id(marketParams), address(morphoVault)).supplyShares;
    }

    function positionAssets(MarketParams memory marketParams) internal view returns (uint256) {
        return positionShares(marketParams)
            * marketAssets(marketParams)
            / morpho.market(MarketParamsLib.id(marketParams)).totalSupplyShares;
    }

    function marketAssets(MarketParams memory marketParams) internal view returns (uint256) {
        return morpho.market(MarketParamsLib.id(marketParams)).totalSupplyAssets;
    }

}

contract MorphoSetSupplyQueueMorphoFailureTests is MorphoTestBase {

    function test_setSupplyQueueMorpho_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.setSupplyQueueMorpho(address(morphoVault), new Id[](0));
    }

    function test_setSupplyQueueMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.setSupplyQueueMorpho(makeAddr("fake-vault"), new Id[](0));
    }

}

contract MorphoSetSupplyQueueMorphoSuccessTests is MorphoTestBase {

    function test_setSupplyQueueMorpho() external {
        // Switch order of existing markets
        Id[] memory supplyQueueUSDC = new Id[](2);
        supplyQueueUSDC[0] = MarketParamsLib.id(market1);
        supplyQueueUSDC[1] = MarketParamsLib.id(market2);

        // No supply queue to start, but caps are above zero
        assertEq(morphoVault.supplyQueueLength(), 0);

        vm.prank(relayer);
        mainnetController.setSupplyQueueMorpho(address(morphoVault), supplyQueueUSDC);

        assertEq(morphoVault.supplyQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.supplyQueue(0)), Id.unwrap(MarketParamsLib.id(market1)));
        assertEq(Id.unwrap(morphoVault.supplyQueue(1)), Id.unwrap(MarketParamsLib.id(market2)));
    }

}

contract MorphoUpdateWithdrawQueueMorphoFailureTests is MorphoTestBase {

    function test_updateWithdrawQueueMorpho_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.updateWithdrawQueueMorpho(address(morphoVault), new uint256[](0));
    }

    function test_updateWithdrawQueueMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.updateWithdrawQueueMorpho(makeAddr("fake-vault"), new uint256[](0));
    }

}

contract MorphoUpdateWithdrawQueueMorphoSuccessTests is MorphoTestBase {

    function test_updateWithdrawQueueMorpho() external {
        // Switch order of existing markets
        uint256[] memory newWithdrawQueueUsdc  = new uint256[](14);
        Id[]      memory startingWithdrawQueue = new Id[](14);

        // Set all markets in same order then adjust
        for (uint256 i = 0; i < 14; i++) {
            newWithdrawQueueUsdc[i]  = i;
            startingWithdrawQueue[i] = morphoVault.withdrawQueue(i);
        }

        assertEq(morphoVault.withdrawQueueLength(), 14);

        assertEq(Id.unwrap(morphoVault.withdrawQueue(11)), Id.unwrap(MarketParamsLib.id(market1)));
        assertEq(Id.unwrap(morphoVault.withdrawQueue(13)), Id.unwrap(MarketParamsLib.id(market2)));

        // Switch order of market1 and market2
        newWithdrawQueueUsdc[11] = 13;
        newWithdrawQueueUsdc[13] = 11;

        vm.prank(relayer);
        mainnetController.updateWithdrawQueueMorpho(address(morphoVault), newWithdrawQueueUsdc);

        assertEq(morphoVault.withdrawQueueLength(), 14);

        assertEq(Id.unwrap(morphoVault.withdrawQueue(11)), Id.unwrap(MarketParamsLib.id(market2)));
        assertEq(Id.unwrap(morphoVault.withdrawQueue(13)), Id.unwrap(MarketParamsLib.id(market1)));

        // Ensure the rest is kept in order
        for (uint256 i = 0; i < 14; i++) {
            if (i == 11 || i == 13) continue;
            assertEq(Id.unwrap(morphoVault.withdrawQueue(i)), Id.unwrap(startingWithdrawQueue[i]));
        }
    }

}

contract MorphoReallocateMorphoFailureTests is MorphoTestBase {

    function test_reallocateMorpho_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.reallocateMorpho(address(morphoVault), new MarketAllocation[](0));
    }

    function test_reallocateMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/invalid-action");
        mainnetController.reallocateMorpho(makeAddr("fake-vault"), new MarketAllocation[](0));
    }

}

contract MorphoReallocateMorphoSuccessTests is MorphoTestBase {

    function test_reallocateMorpho() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        vm.stopPrank();

        // Refresh markets so calculations don't include interest
        vm.prank(relayer);
        mainnetController.depositERC4626(address(morphoVault), 0);

        uint256 market1Position = positionAssets(market1);
        uint256 market2Position = positionAssets(market2);

        uint256 market1Assets = marketAssets(market1);
        uint256 market2Assets = marketAssets(market2);

        assertEq(market1Position, 356_456_521.341763767525558015e18);
        assertEq(market2Position, 50_038_784.076802509703226888e18);

        assertEq(market1Assets, 390_003_166.284505547080982600e18);
        assertEq(market2Assets, 50_038_786.142322219196324919e18);

        // Move 1m from market1 to market2
        MarketAllocation[] memory reallocations = new MarketAllocation[](2);
        reallocations[0] = MarketAllocation({
            marketParams : market1,
            assets       : market1Position - 1_000_000e18
        });
        reallocations[1] = MarketAllocation({
            marketParams : market2,
            assets       : type(uint256).max
        });

        vm.prank(relayer);
        mainnetController.reallocateMorpho(address(morphoVault), reallocations);

        uint256 positionInterest = 9_803.525491215426215841e18;
        uint256 market1Interest  = 223.610631168657703153e18;
        uint256 market2Interest  = 9_803.525797810824423503e18;  // Slightly higher than position from external liquidity

        // Interest from position1 moves as well, resulting position is as specified
        assertEq(positionAssets(market1), market1Position - 1_000_000e18);
        assertEq(positionAssets(market2), market2Position + 1_000_000e18 + positionInterest);

        assertEq(marketAssets(market1), market1Assets - 1_000_000e18 + market1Interest);
        assertEq(marketAssets(market2), market2Assets + 1_000_000e18 + market2Interest);

        // Overwrite values for simpler assertions
        market1Position = positionAssets(market1);
        market2Position = positionAssets(market2);
        market1Assets   = marketAssets(market1);
        market2Assets   = marketAssets(market2);

        // Move another 500k from market1 to market2
        reallocations = new MarketAllocation[](2);
        reallocations[0] = MarketAllocation({
            marketParams : market1,
            assets       : market1Position - 500_000e18
        });
        reallocations[1] = MarketAllocation({
            marketParams : market2,
            assets       : market2Position + 500_000e18
        });

        vm.prank(relayer);
        mainnetController.reallocateMorpho(address(morphoVault), reallocations);

        // No new interest has been accounted for so values are exact
        assertEq(positionAssets(market1), market1Position - 500_000e18);
        assertEq(positionAssets(market2), market2Position + 500_000e18);

        assertEq(marketAssets(market1), market1Assets - 500_000e18);
        assertEq(marketAssets(market2), market2Assets + 500_000e18);
    }

}
