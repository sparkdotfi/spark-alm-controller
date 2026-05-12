// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IPSMFacet }  from "../../src/facets/psm/IPSMFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface IPSMLike {

    event Fill(uint256 wad);

    function buf() external view returns (uint256);

    function rush() external view returns (uint256);

}

abstract contract PSM_TestBase is ForkTestBase {

    IERC20Like internal constant DAI  = IERC20Like(Ethereum.DAI);
    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);
    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    IPSMLike internal constant PSM = IPSMLike(Ethereum.PSM);

    function setUp() public override {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setUSDSVault(vault);
    }

}

contract MainnetController_PSM_SwapUSDSToUSDC_Tests is PSM_TestBase {

    function test_swapUSDSToUSDC_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUSDSToUSDC(1e6);
    }

    function test_swapUSDSToUSDC_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.swapUSDSToUSDC(1e6);
    }

    function test_swapUSDSToUSDC_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.psmUSDSToUSDCSwapRateLimitKey(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.swapUSDSToUSDC(1e6);
    }

    function test_swapUSDSToUSDC_rateLimitBoundary() external {
        deal(Ethereum.USDS, address(almProxy), 10_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.swapUSDSToUSDC(5_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.swapUSDSToUSDC(5_000_000e6);
    }

    function test_swapUSDSToUSDC() external {
        vm.prank(allocator);
        mainnetController.mintUSDS(1e18);

        assertEq(USDS.balanceOf(address(almProxy)),          1e18);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY + 1e18);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDSToUSDC(1e6);

        vm.prank(allocator);
        mainnetController.swapUSDSToUSDC(1e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(address(almProxy)),          0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM + 1e18);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY + 1e18);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM - 1e6);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);
    }

    function test_swapUSDSToUSDC_rateLimited() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(mainnetController.usdsMintRateLimitKey());
        vm.stopPrank();

        bytes32 key = mainnetController.psmUSDSToUSDCSwapRateLimitKey();

        vm.startPrank(allocator);

        mainnetController.mintUSDS(9_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);
        assertEq(USDS.balanceOf(address(almProxy)),   9_000_000e18);
        assertEq(USDC.balanceOf(address(almProxy)),   0);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDSToUSDC(1_000_000e6);
        mainnetController.swapUSDSToUSDC(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e6);
        assertEq(USDS.balanceOf(address(almProxy)),   8_000_000e18);
        assertEq(USDC.balanceOf(address(almProxy)),   1_000_000e6);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.9984e6);
        assertEq(USDS.balanceOf(address(almProxy)),   8_000_000e18);
        assertEq(USDC.balanceOf(address(almProxy)),   1_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDSToUSDC(4_249_999.9984e6);
        mainnetController.swapUSDSToUSDC(4_249_999.9984e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
        assertEq(USDS.balanceOf(address(almProxy)),   3_750_000.0016e18);
        assertEq(USDC.balanceOf(address(almProxy)),   5_249_999.9984e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUSDSToUSDC(1);

        vm.stopPrank();
    }

}

contract MainnetController_PSM_SwapUSDCToUSDS_Tests is PSM_TestBase {

    function test_swapUSDCToUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.swapUSDCToUSDS(1e6);
    }

    function test_swapUSDCToUSDS_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.swapUSDCToUSDS(1e6);
    }

    function test_swapUSDCToUSDS_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.psmUSDCToUSDSSwapRateLimitKey(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(1e6);
    }

    function test_swapUSDCToUSDS_rateLimitBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 10_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(5_000_000e6 + 1);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(5_000_000e6);
    }

    function test_swapUSDCToUSDS_incompleteFillBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(mainnetController.psmUSDCToUSDSSwapRateLimitKey());
        vm.stopPrank();

        // The line is just over 2.1 billion, this condition will allow DAI to get minted to get to
        // 2 billion in art, and then another fill to get to the `line`.
        deal(Ethereum.USDC, POCKET, 2_000_000_000e6);

        uint256 fillAmount = PSM.rush();

        assertEq(fillAmount, 3_008_396.9118e18); // Only first fill amount

        // NOTE: art == dai here because rate is 1 for PSM ilk
        ( uint256 art, , , uint256 line, ) = dss.vat.ilks(PSM_ILK);

        assertEq(art,              2_396_991_603.0882e18);
        assertEq(art + fillAmount, 2_400_000_000e18);
        assertEq(line / 1e27,      2_796_991_603.0882e18);

        // The first fill increases the art to 2.4 billion and the USDC balance of the PSM to roughly 2.4 billion.
        // For the second fill, the USDC balance + buffer option is over 2.8 billion so it instead fills to the line
        // which is 2.796 billion.
        uint256 expectedFillAmount2 = line / 1e27 - 2_400_000_000e18;

        assertEq(expectedFillAmount2, 396_991_603.0882e18);

        // Max amount of DAI that can be swapped, converted to USDC precision
        uint256 maxSwapAmount = (DAI_BAL_PSM + fillAmount + expectedFillAmount2) / 1e12;

        assertEq(maxSwapAmount, 813_630_294.354574e6);

        deal(Ethereum.USDC, address(almProxy), maxSwapAmount + 1);

        vm.expectRevert("DssLitePsm/nothing-to-fill");
        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(maxSwapAmount + 1);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(maxSwapAmount);

        assertEq(USDS.balanceOf(address(almProxy)), maxSwapAmount * 1e12);

        ( art, , , , ) = dss.vat.ilks(PSM_ILK);

        // art has now been filled to the debt ceiling and there is no DAI left in the PSM.
        assertEq(art, line / 1e27);
        assertEq(art, 2_796_991_603.0882e18);

        assertEq(DAI.balanceOf(Ethereum.PSM), 0);
    }

    function test_swapUSDCToUSDS() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        assertEq(USDS.balanceOf(address(almProxy)),          0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(1e6);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(1e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDS.balanceOf(address(almProxy)),          1e18);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY + 1e18);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM - 1e18);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY - 1e18);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM + 1e6);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);
    }

    function test_swapUSDCToUSDS_exactBalanceNoRefill() external {
        uint256 swapAmount = DAI_BAL_PSM / 1e12;

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.psmUSDCToUSDSSwapRateLimitKey(), swapAmount, 0);
        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), swapAmount);

        assertEq(USDS.balanceOf(address(almProxy)),          0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY);

        assertEq(USDC.balanceOf(address(almProxy)),          swapAmount);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);

        ( uint256 Art1, , , , ) = dss.vat.ilks(PSM_ILK);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(swapAmount);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(swapAmount);

        ( uint256 Art2, , , , ) = dss.vat.ilks(PSM_ILK);

        assertEq(Art1, Art2);  // Fill was not called on exact amount

        assertEq(USDS.balanceOf(address(almProxy)),          DAI_BAL_PSM);  // Drain PSM
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY + DAI_BAL_PSM);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      0);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY - DAI_BAL_PSM);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     USDC_BAL_PSM + swapAmount);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);
    }

    function test_swapUSDCToUSDS_partialRefill() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.psmUSDCToUSDSSwapRateLimitKey(), 415_000_000e6, 0);
        vm.stopPrank();

        assertEq(DAI_BAL_PSM, 413_630_294.354574e18);

        // PSM is not fillable at current fork so need to deal USDC
        uint256 fillAmount = PSM.rush();

        assertEq(fillAmount, 0);

        ( uint256 art, , , uint256 line, ) = dss.vat.ilks(PSM_ILK);

        // art is less than line, but USDC balance needs to increase to allow minting
        assertEq(USDC.balanceOf(POCKET) * 1e12 + PSM.buf(), 2_383_361_309.129139e18);
        assertEq(art,                                       2_396_991_603.0882e18);
        assertEq(line / 1e27,                               2_796_991_603.0882e18);

        // This will bring USDC balance + buffer over art
        deal(Ethereum.USDC, POCKET, 2_000_000_000e6);

        assertEq(USDC.balanceOf(POCKET) * 1e12 + PSM.buf(), 2_400_000_000e18);
        assertEq(art,                                       2_396_991_603.0882e18);
        assertEq(line / 1e27,                               2_796_991_603.0882e18);

        ( art, , , line, ) = dss.vat.ilks(PSM_ILK);

        fillAmount = PSM.rush();

        assertEq(fillAmount, 3_008_396.9118e18);
        assertEq(fillAmount, 2_400_000_000e18 - art);

        // Higher than balance of DAI, less than fillAmount + balance
        deal(Ethereum.USDC, address(almProxy), 415_000_000e6);

        assertEq(USDS.balanceOf(address(almProxy)),          0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY);

        assertEq(USDC.balanceOf(address(almProxy)),          415_000_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     2_000_000_000e6);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(415_000_000e6);

        vm.expectEmit(Ethereum.PSM);
        emit IPSMLike.Fill(fillAmount);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(415_000_000e6);

        ( art, , , , ) = dss.vat.ilks(PSM_ILK);

        // Amount minted brings art to usdc balance + buffer
        assertEq(art, 2_400_000_000e18);

        assertEq(USDS.balanceOf(address(almProxy)),          415_000_000e18);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY + 415_000_000e18);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM + fillAmount - 415_000_000e18);
        assertEq(DAI.balanceOf(Ethereum.PSM),      1_638_691.266374e18);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY + fillAmount - 415_000_000e18);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     2_415_000_000e6);  // 2 billion + 415 million

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);
    }

    function test_swapUSDCToUSDS_multipleRefills() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.psmUSDCToUSDSSwapRateLimitKey(), 500_000_000e6, 0);
        vm.stopPrank();

        assertEq(DAI_BAL_PSM, 413_630_294.354574e18);

        // PSM is not fillable at current fork so need to deal USDC
        uint256 fillAmount = PSM.rush();

        assertEq(fillAmount, 0);

        ( uint256 art, , , uint256 line, ) = dss.vat.ilks(PSM_ILK);

        // art is less than line, but USDC balance needs to increase to allow minting
        assertEq(USDC.balanceOf(POCKET) * 1e12 + PSM.buf(), 2_383_361_309.129139e18);
        assertEq(art,                                       2_396_991_603.0882e18);
        assertEq(line / 1e27,                               2_796_991_603.0882e18);

        // This will bring USDC balance + buffer over art
        deal(Ethereum.USDC, POCKET, 2_000_000_000e6);

        assertEq(USDC.balanceOf(POCKET) * 1e12 + PSM.buf(), 2_400_000_000e18);
        assertEq(art,                                       2_396_991_603.0882e18);
        assertEq(line / 1e27,                               2_796_991_603.0882e18);

        ( art, , , line, ) = dss.vat.ilks(PSM_ILK);

        fillAmount = PSM.rush();

        assertEq(fillAmount, 3_008_396.9118e18);
        assertEq(fillAmount, 2_400_000_000e18 - art);  // NOTE: This is just the first fill amount

        // The first fill increases the art to 2.4 billion and the USDC balance of the PSM to roughly 2.4 billion.
        // For the second fill, the USDC balance + buffer option is over 2.8 billion so it instead fills to the line
        // which is 2.796 billion.
        uint256 expectedFillAmount2 = line / 1e27 - 2_400_000_000e18;

        assertEq(expectedFillAmount2, 396_991_603.0882e18);

        deal(Ethereum.USDC, address(almProxy), 500_000_000e6);  // Higher than balance of DAI + fillAmount

        assertEq(USDS.balanceOf(address(almProxy)),          0);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY);

        assertEq(USDC.balanceOf(address(almProxy)),          500_000_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     2_000_000_000e6);

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);

        assertEq(art + fillAmount + expectedFillAmount2, line / 1e27);  // Two fills will increase art to the debt ceiling

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(500_000_000e6);

        vm.expectEmit(Ethereum.PSM);
        emit IPSMLike.Fill(fillAmount);

        vm.expectEmit(Ethereum.PSM);
        emit IPSMLike.Fill(expectedFillAmount2);

        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(500_000_000e6);

        ( art, , , , ) = dss.vat.ilks(PSM_ILK);

        // art has now been filled to the debt ceiling.
        assertEq(art, line / 1e27);
        assertEq(art, 2_796_991_603.0882e18);

        assertEq(USDS.balanceOf(address(almProxy)),          500_000_000e18);
        assertEq(USDS.balanceOf(address(mainnetController)), 0);
        assertEq(USDS.totalSupply(),                         USDS_SUPPLY + 500_000_000e18);

        assertEq(DAI.balanceOf(address(almProxy)), 0);
        assertEq(DAI.balanceOf(Ethereum.PSM),      DAI_BAL_PSM + fillAmount + expectedFillAmount2 - 500_000_000e18);
        assertEq(DAI.balanceOf(Ethereum.PSM),      313_630_294.354574e18);
        assertEq(DAI.totalSupply(),                DAI_SUPPLY + fillAmount + expectedFillAmount2 - 500_000_000e18);

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.balanceOf(POCKET),                     2_500_000_000e6);  // 2 billion + 500 millions

        assertEq(USDS.allowance(buffer,            vault),             type(uint256).max);
        assertEq(USDS.allowance(address(almProxy), Ethereum.DAI_USDS), 0);
        assertEq(DAI.allowance(address(almProxy),  Ethereum.PSM),      0);
    }

    function test_swapUSDCToUSDS_rateLimited() external {
        bytes32 key = mainnetController.psmUSDCToUSDSSwapRateLimitKey();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6);

        vm.startPrank(allocator);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);
        assertEq(USDC.balanceOf(address(almProxy)),   10_000_000e6);
        assertEq(USDS.balanceOf(address(almProxy)),   0);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(400_000e6);
        mainnetController.swapUSDCToUSDS(400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_600_000e6);
        assertEq(USDC.balanceOf(address(almProxy)),   9_600_000e6);
        assertEq(USDS.balanceOf(address(almProxy)),   400_000e18);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_849_999.998400e6);
        assertEq(USDC.balanceOf(address(almProxy)),   9_600_000e6);
        assertEq(USDS.balanceOf(address(almProxy)),   400_000e18);

        vm.expectEmit(address(mainnetController));
        emit IPSMFacet.PSMSwapUSDCToUSDS(4_849_999.998400e6);
        mainnetController.swapUSDCToUSDS(4_849_999.998400e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
        assertEq(USDC.balanceOf(address(almProxy)),   4_750_000.001600e6);
        assertEq(USDS.balanceOf(address(almProxy)),   5_249_999.998400000000000000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUSDCToUSDS(1);

        vm.stopPrank();
    }

    function test_swapUSDSToUSDC_zeroUSDSToUSDCSwapRateLimit() external {
        bytes32 usdsToUsdcKey = mainnetController.psmUSDSToUSDCSwapRateLimitKey();
        bytes32 usdcToUsdsKey = mainnetController.psmUSDCToUSDSSwapRateLimitKey();

        vm.prank(allocator);
        mainnetController.mintUSDS(1_000_000e18);

        vm.prank(allocator);
        mainnetController.swapUSDSToUSDC(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdsToUsdcKey), 4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(usdcToUsdsKey), 5_000_000e6);

        // Partial swap USDC to USDS
        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(500_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdsToUsdcKey), 4_500_000e6);
        assertEq(rateLimits.getCurrentRateLimit(usdcToUsdsKey), 4_500_000e6);

        // Zero USDS to USDC swap rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(usdsToUsdcKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(usdsToUsdcKey), 0);
        assertEq(rateLimits.getCurrentRateLimit(usdcToUsdsKey), 4_500_000e6);

        // Partial swap USDC to USDS
        vm.prank(allocator);
        mainnetController.swapUSDCToUSDS(500_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdsToUsdcKey), 0); // No change
        assertEq(rateLimits.getCurrentRateLimit(usdcToUsdsKey), 4_000_000e6);
    }

    function testFuzz_swapUSDCToUSDS(uint256 swapAmount) external {
        swapAmount = _bound(swapAmount, 1e6, 1_000_000_000e6);

        deal(Ethereum.USDC, address(almProxy), swapAmount);

        uint256 usdsBalanceBefore = USDS.balanceOf(address(almProxy));

        // NOTE: Doing a low-level call here because if the full amount can't be swapped, it should revert
        vm.prank(allocator);
        ( bool success, ) = address(mainnetController).call(
            abi.encodeWithSignature("swapUSDCToUSDS(uint256)", swapAmount)
        );

        if (success) {
            assertEq(USDS.balanceOf(address(almProxy)), usdsBalanceBefore + swapAmount * 1e12);
        }
    }

}
