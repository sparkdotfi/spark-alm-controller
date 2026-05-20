// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IUSDSFacet } from "../../src/facets/usds/IUSDSFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

abstract contract USDS_TestBase is ForkTestBase {

    IERC20Like internal constant USDS = IERC20Like(Ethereum.USDS);

    function setUp() public override virtual {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.usds_setVault(vault);
    }

}

contract MainnetController_USDS_Mint_Tests is USDS_TestBase {

    bytes32 internal mintKey;

    function setUp() public override virtual {
        super.setUp();

        mintKey = mainnetController.usds_mintRateLimitKey();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mintKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_mintUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.usds_mint(1e18);
    }

    function test_mintUSDS_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.usds_mint(1e18);
    }

    function test_mintUSDS_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mintKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.usds_mint(1e18);
    }

    function test_mintUSDS_rateLimitBoundary() external {
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.usds_mint(5_000_000e18 + 1);

        vm.prank(allocator);
        mainnetController.usds_mint(5_000_000e18);
    }

    function test_mintUSDS() external {
        ( uint256 ink, uint256 art ) = dss.vat.urns(ilk, vault);
        ( uint256 Art, , , , )       = dss.vat.ilks(ilk);

        assertEq(dss.vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IUSDSFacet.USDSMint(1e18);

        vm.prank(allocator);
        mainnetController.usds_mint(1e18);

        _assertReentrancyGuardWrittenToTwice();

        ( ink, art )   = dss.vat.urns(ilk, vault);
        ( Art, , , , ) = dss.vat.ilks(ilk);

        assertEq(dss.vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(USDS.balanceOf(address(almProxy)), 1e18);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY + 1e18);
    }

    function test_mintUSDS_rateLimited() external {
        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       0);

        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       1_000_000e18);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_249_999.9999999999999984e18);
        assertEq(USDS.balanceOf(address(almProxy)),       1_000_000e18);

        vm.prank(allocator);
        mainnetController.usds_mint(4_249_999.9999999999999984e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 0);
        assertEq(USDS.balanceOf(address(almProxy)),       5_249_999.9999999999999984e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.usds_mint(1);
    }

}

contract MainnetController_USDS_Burn_Tests is USDS_TestBase {

    bytes32 internal burnKey;
    bytes32 internal mintKey;

    function setUp() public override virtual {
        super.setUp();

        burnKey = mainnetController.usds_burnRateLimitKey();
        mintKey = mainnetController.usds_mintRateLimitKey();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(burnKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_burnUSDS_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.usds_burn(1e18);
    }

    function test_burnUSDS_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.usds_burn(1e18);
    }

    function test_burnUSDS_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(burnKey, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.usds_burn(1e18);
    }

    function test_burnUSDS() external {
        // Setup
        vm.expectEmit(address(mainnetController));
        emit IUSDSFacet.USDSMint(1e18);

        vm.prank(allocator);
        mainnetController.usds_mint(1e18);

        ( uint256 ink, uint256 art ) = dss.vat.urns(ilk, vault);
        ( uint256 Art, , , , )       = dss.vat.ilks(ilk);

        assertEq(dss.vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(USDS.balanceOf(address(almProxy)), 1e18);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY + 1e18);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IUSDSFacet.USDSBurn(1e18);

        vm.prank(allocator);
        mainnetController.usds_burn(1e18);

        _assertReentrancyGuardWrittenToTwice();

        ( ink, art )   = dss.vat.urns(ilk, vault);
        ( Art, , , , ) = dss.vat.ilks(ilk);

        assertEq(dss.vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(USDS.balanceOf(address(almProxy)), 0);
        assertEq(USDS.totalSupply(),                USDS_SUPPLY);
    }

    function test_burnUSDS_rateLimited() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mintKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       0);

        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       1_000_000e18);

        vm.prank(allocator);
        mainnetController.usds_burn(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_500_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_500_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       500_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       500_000e18);

        vm.prank(allocator);
        mainnetController.usds_burn(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_500_000e18);
        assertEq(USDS.balanceOf(address(almProxy)),       0);
    }

    function test_burnUSDS_zeroMintRateLimit() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mintKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.usds_mint(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.usds_burn(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_500_000e18);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_500_000e18);

        // Zero mint rate limit
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mintKey, 0, 0);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 0);
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_500_000e18);

        vm.prank(allocator);
        mainnetController.usds_burn(500_000e18);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 0);  // stays at 0
        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_000_000e18);
    }

}
