// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id, MarketAllocation } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract MorphoTestBase is ForkTestBase {

    address constant CBBTC              = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant CBBTC_USDC_ORACLE  = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;
    address constant MORPHO_DEFAULT_IRM = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    IMetaMorpho morphoVault = IMetaMorpho(Base.MORPHO_VAULT_SUSDC);
    IMorpho     morpho      = IMorpho(Base.MORPHO);

    MarketParams usdcIdle = MarketParams({
        loanToken       : Base.USDC,
        collateralToken : address(0),
        oracle          : address(0),
        irm             : address(0),
        lltv            : 0
    });
    MarketParams usdcCBBTC = MarketParams({
        loanToken       : Base.USDC,
        collateralToken : CBBTC,
        oracle          : CBBTC_USDC_ORACLE,
        irm             : MORPHO_DEFAULT_IRM,
        lltv            : 0.86e18
    });

    function setUp() public override {
        super.setUp();

        // Spell onboarding
        vm.startPrank(Base.SPARK_EXECUTOR);
        morphoVault.setIsAllocator(address(almProxy), true);
        morphoVault.setIsAllocator(address(relayer),  false);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 25340000;  // Jan 21, 2024
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
        foreignController.setSupplyQueueMorpho(address(morphoVault), new Id[](0));
    }

    function test_setSupplyQueueMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("ForeignController/invalid-action");
        foreignController.setSupplyQueueMorpho(makeAddr("fake-vault"), new Id[](0));
    }

}

contract MorphoSetSupplyQueueMorphoSuccessTests is MorphoTestBase {

    function test_setSupplyQueueMorpho() external {
        // Switch order of existing markets
        Id[] memory supplyQueueUSDC = new Id[](2);
        supplyQueueUSDC[0] = MarketParamsLib.id(usdcIdle);
        supplyQueueUSDC[1] = MarketParamsLib.id(usdcCBBTC);

        assertEq(morphoVault.supplyQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.supplyQueue(0)), Id.unwrap(MarketParamsLib.id(usdcCBBTC)));
        assertEq(Id.unwrap(morphoVault.supplyQueue(1)), Id.unwrap(MarketParamsLib.id(usdcIdle)));

        vm.prank(relayer);
        foreignController.setSupplyQueueMorpho(address(morphoVault), supplyQueueUSDC);

        assertEq(morphoVault.supplyQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.supplyQueue(0)), Id.unwrap(MarketParamsLib.id(usdcIdle)));
        assertEq(Id.unwrap(morphoVault.supplyQueue(1)), Id.unwrap(MarketParamsLib.id(usdcCBBTC)));
    }

}

contract MorphoUpdateWithdrawQueueMorphoFailureTests is MorphoTestBase {

    function test_updateWithdrawQueueMorpho_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.updateWithdrawQueueMorpho(address(morphoVault), new uint256[](0));
    }

    function test_updateWithdrawQueueMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("ForeignController/invalid-action");
        foreignController.updateWithdrawQueueMorpho(makeAddr("fake-vault"), new uint256[](0));
    }

}

contract MorphoUpdateWithdrawQueueMorphoSuccessTests is MorphoTestBase {

    function test_updateWithdrawQueueMorpho() external {
        // Switch order of existing markets
        uint256[] memory withdrawQueueUsdc = new uint256[](2);
        withdrawQueueUsdc[0] = 1;
        withdrawQueueUsdc[1] = 0;

        assertEq(morphoVault.withdrawQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.withdrawQueue(0)), Id.unwrap(MarketParamsLib.id(usdcIdle)));
        assertEq(Id.unwrap(morphoVault.withdrawQueue(1)), Id.unwrap(MarketParamsLib.id(usdcCBBTC)));

        vm.prank(relayer);
        foreignController.updateWithdrawQueueMorpho(address(morphoVault), withdrawQueueUsdc);

        assertEq(morphoVault.withdrawQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.withdrawQueue(0)), Id.unwrap(MarketParamsLib.id(usdcCBBTC)));
        assertEq(Id.unwrap(morphoVault.withdrawQueue(1)), Id.unwrap(MarketParamsLib.id(usdcIdle)));
    }

}

contract MorphoReallocateMorphoFailureTests is MorphoTestBase {

    function test_reallocateMorpho_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.reallocateMorpho(address(morphoVault), new MarketAllocation[](0));
    }

    function test_reallocateMorpho_invalidVault() external {
        vm.prank(relayer);
        vm.expectRevert("ForeignController/invalid-action");
        foreignController.reallocateMorpho(makeAddr("fake-vault"), new MarketAllocation[](0));
    }

}

contract MorphoReallocateMorphoSuccessTests is MorphoTestBase {

    function test_reallocateMorpho() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                foreignController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        vm.stopPrank();

        // Refresh markets so calculations don't include interest
        vm.prank(relayer);
        foreignController.depositERC4626(address(morphoVault), 0);

        uint256 positionCBBTC = positionAssets(usdcCBBTC);
        uint256 positionIdle  = positionAssets(usdcIdle);

        uint256 marketAssetsCBBTC = marketAssets(usdcCBBTC);
        uint256 marketAssetsIdle  = marketAssets(usdcIdle);

        assertEq(positionCBBTC, 12_128_319.737383e6);
        assertEq(positionIdle,  0);

        assertEq(marketAssetsCBBTC, 56_494_357.047568e6);
        assertEq(marketAssetsIdle,  5.205521e6);

        deal(Base.USDC, address(almProxy), 1_000_000e6);
        vm.prank(relayer);
        foreignController.depositERC4626(address(morphoVault), 1_000_000e6);

        assertEq(positionAssets(usdcCBBTC), positionCBBTC + 1_000_000e6);
        assertEq(positionAssets(usdcIdle),  0);

        assertEq(marketAssets(usdcCBBTC), marketAssetsCBBTC + 1_000_000e6);
        assertEq(marketAssets(usdcIdle),  marketAssetsIdle);

        // Move new allocation into idle market
        MarketAllocation[] memory reallocations = new MarketAllocation[](2);
        reallocations[0] = MarketAllocation({
            marketParams : usdcCBBTC,
            assets       : positionCBBTC
        });
        reallocations[1] = MarketAllocation({
            marketParams : usdcIdle,
            assets       : 1_000_000e6
        });

        vm.prank(relayer);
        foreignController.reallocateMorpho(address(morphoVault), reallocations);

        // NOTE: No interest is accrued because deposit coverered all markets and is atomic
        assertEq(positionAssets(usdcCBBTC), positionCBBTC);
        assertEq(positionAssets(usdcIdle),  1_000_000e6);

        assertEq(marketAssets(usdcCBBTC), marketAssetsCBBTC);
        assertEq(marketAssets(usdcIdle),  marketAssetsIdle + 1_000_000e6);

        // Move 400k back into CBBTC, note order has changed because of pulling from idle market
        reallocations = new MarketAllocation[](2);
        reallocations[0] = MarketAllocation({
            marketParams : usdcIdle,
            assets       : 600_000e6
        });
        reallocations[1] = MarketAllocation({
            marketParams : usdcCBBTC,
            assets       : positionCBBTC + 400_000e6
        });

        vm.prank(relayer);
        foreignController.reallocateMorpho(address(morphoVault), reallocations);

        assertEq(positionAssets(usdcCBBTC), positionCBBTC + 400_000e6);
        assertEq(positionAssets(usdcIdle),  600_000e6);

        assertEq(marketAssets(usdcCBBTC), marketAssetsCBBTC + 400_000e6);
        assertEq(marketAssets(usdcIdle),  marketAssetsIdle + 600_000e6);
    }

}
