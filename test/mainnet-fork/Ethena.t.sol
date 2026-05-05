// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { IUSDEFacet } from "../../src/facets/usde/IUSDEFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IEthenaMinterLike {

    event DelegatedSignerInitiated(address indexed delegateTo, address indexed initiatedBy);

    event DelegatedSignerRemoved(address indexed removedSigner, address indexed initiatedBy);

    function delegatedSigner(address signer, address owner) external view returns (uint8);

}

interface ISUSDELike {

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256         assets,
        uint256         shares
    );

}

abstract contract Ethena_TestBase is ForkTestBase {

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }

}

contract MainnetController_Ethena_SetDelegatedSigner_Tests is Ethena_TestBase {

    function test_setDelegatedSigner_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setDelegatedSigner(makeAddr("signer"));
    }

    function test_setDelegatedSigner_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.setDelegatedSigner(makeAddr("signer"));
    }

    function test_setDelegatedSigner() external {
        address signer = makeAddr("signer");

        assertEq(IEthenaMinterLike(ETHENA_MINTER).delegatedSigner(signer, address(almProxy)), 0);  // REJECTED

        vm.record();

        vm.expectEmit(ETHENA_MINTER);
        emit IEthenaMinterLike.DelegatedSignerInitiated({
            delegateTo  : signer,
            initiatedBy : address(almProxy)
        });

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDESetDelegatedSigner(signer);

        vm.prank(allocator);
        mainnetController.setDelegatedSigner(signer);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IEthenaMinterLike(ETHENA_MINTER).delegatedSigner(signer, address(almProxy)), 1);  // PENDING
    }

}

contract MainnetController_Ethena_RemoveDelegatedSigner_Tests is Ethena_TestBase {

    function test_removeDelegatedSigner_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.removeDelegatedSigner(makeAddr("signer"));
    }

    function test_removeDelegatedSigner_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.removeDelegatedSigner(makeAddr("signer"));
    }

    function test_removeDelegatedSigner() external {
        address signer = makeAddr("signer");

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDESetDelegatedSigner(signer);

        vm.prank(allocator);
        mainnetController.setDelegatedSigner(signer);

        assertEq(IEthenaMinterLike(ETHENA_MINTER).delegatedSigner(signer, address(almProxy)), 1);  // PENDING

        vm.record();

        vm.expectEmit(ETHENA_MINTER);
        emit IEthenaMinterLike.DelegatedSignerRemoved({
            removedSigner : signer,
            initiatedBy   : address(almProxy)
        });

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDERemoveDelegatedSigner(signer);

        vm.prank(allocator);
        mainnetController.removeDelegatedSigner(signer);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(IEthenaMinterLike(ETHENA_MINTER).delegatedSigner(signer, address(almProxy)), 0);  // REJECTED
    }

}

contract MainnetController_Ethena_PrepareUSDEMint_Tests is Ethena_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.usdeMintRateLimitKey();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e6, uint256(1_000_000e6) / 4 hours);
    }

    function test_prepareUSDEMint_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.prepareUSDeMint(100);
    }

    function test_prepareUSDEMint_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.prepareUSDeMint(100);
    }

    function test_prepareUSDEMint_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.prepareUSDeMint(1e18);
    }

    function test_prepareUSDEMint_rateLimitBoundary() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 100e6, uint256(100e6) / 1 hours);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.prepareUSDeMint(100e6 + 1);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(100e6);
    }

    function test_prepareUSDEMint() external {
        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareMint(100e6);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(100e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 100e6);
    }

    function test_prepareUSDEMint_rateLimits() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareMint(4_000_000e6);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(4_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e6 - 6400);  // Rounding

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareMint(600_000e6);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(600_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e6 - 6400);  // Rounding
    }

}

contract MainnetController_Ethena_PrepareUSDEBurn_Tests is Ethena_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.usdeBurnRateLimitKey();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_prepareUSDEBurn_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.prepareUSDeBurn(100);
    }

    function test_prepareUSDEBurn_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.prepareUSDeBurn(100);
    }

    function test_prepareUSDEBurn_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(1e18);
    }

    function test_prepareUSDEBurn_rateLimitBoundary() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 100e18, uint256(100e18) / 1 hours);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(100e18 + 1);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(100e18);
    }

    function test_prepareUSDEBurn() external {
        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareBurn(100e18);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 100e18);
    }

    function test_prepareUSDEBurn_rateLimits() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareBurn(4_000_000e18);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e18 - 6400);  // Rounding

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEPrepareBurn(600_000e18);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e18 - 6400);  // Rounding
    }

}

contract MainnetController_Ethena_CooldownAssetsSUSDE_Tests is Ethena_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.usdeCooldownRateLimitKey();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_cooldownAssetsSUSDE_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDE_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDE_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDE_rateLimitBoundary() external {
        // For success case (exchange rate is more than 1:1)
        deal(address(susde), address(almProxy), 100e18);

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 100e18, uint256(100e18) / 1 hours);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(100e18 + 1);

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDE() external {
        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 100e18);

        assertEq(susde.balanceOf(address(almProxy)), 100e18);
        assertEq(usde.balanceOf(silo),               startingSiloBalance);

        vm.record();

        vm.expectEmit(address(susde));
        emit ISUSDELike.Withdraw({
            sender   : address(almProxy),
            receiver : silo,
            owner    : address(almProxy),
            assets   : assets,
            shares   : 100e18
        });

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDECooldownAssets(assets, 100e18);

        vm.prank(allocator);
        uint256 returnedShares = mainnetController.cooldownAssetsSUSDe(assets);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(returnedShares,                     100e18);
        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),               startingSiloBalance + assets);
    }

    function test_cooldownAssetsSUSDE_rateLimits() external {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e18 - 6400);  // Rounding

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e18 - 6400);  // Rounding
    }

}

contract MainnetController_Ethena_CooldownSharesSUSDE_Tests is Ethena_TestBase {

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.usdeCooldownRateLimitKey();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_cooldownSharesSUSDE_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.cooldownSharesSUSDe(100);
    }

    function test_cooldownSharesSUSDE_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.cooldownSharesSUSDe(100);
    }

    function test_cooldownSharesSUSDE_zeroMaxAmount() external {
        deal(address(susde), address(almProxy), 100e18);  // To get past call

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(100e18);
    }

    function test_cooldownSharesSUSDE_rateLimitBoundary() external {
        deal(address(susde), address(almProxy), 100e18);  // For success case

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 100e18, uint256(100e18) / 1 hours);

        uint256 overBoundaryShares = susde.convertToShares(100e18 + 2);
        uint256 boundaryShares     = susde.convertToShares(100e18 + 1);

        // Demonstrate how rounding works
        assertEq(susde.previewRedeem(overBoundaryShares), 100e18 + 1);
        assertEq(susde.previewRedeem(boundaryShares),     100e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(overBoundaryShares);

        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(boundaryShares);
    }

    function test_cooldownSharesSUSDE() external {
        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        deal(address(susde), address(almProxy), 100e18);

        assertEq(susde.balanceOf(address(almProxy)), 100e18);
        assertEq(usde.balanceOf(silo),               startingSiloBalance);

        vm.record();

        vm.expectEmit(address(susde));
        emit ISUSDELike.Withdraw({
            sender   : address(almProxy),
            receiver : silo,
            owner    : address(almProxy),
            assets   : assets,
            shares   : 100e18
        });

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDECooldownShares(100e18, assets);

        vm.prank(allocator);
        uint256 returnedAssets = mainnetController.cooldownSharesSUSDe(100e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(returnedAssets, assets);

        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),               startingSiloBalance + assets);
    }

    function test_cooldownSharesSUSDE_rateLimits() external {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(allocator);
        uint256 returnedAssets = mainnetController.cooldownSharesSUSDe(4_000_000e18);

        uint256 assets1 = susde.convertToAssets(4_000_000e18);

        assertEq(returnedAssets, assets1);

        assertGe(assets1, 4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1 + (1_000_000e18 - 6400));  // Rounding

        vm.prank(allocator);
        returnedAssets = mainnetController.cooldownSharesSUSDe(600_000e18);

        uint256 assets2 = susde.convertToAssets(600_000e18);

        assertEq(returnedAssets, assets2);

        assertGe(assets2, 600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1 + (1_000_000e18 - 6400) - assets2);
    }

}

contract MainnetController_Ethena_UnstakeSUSDE_Tests is Ethena_TestBase {

    function test_unstakeSUSDE_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.unstakeSUSDe();
    }

    function test_unstakeSUSDE_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.unstakeSUSDe();
    }

    function test_unstakeSUSDE_cooldownBoundary() external {
        // Exchange rate greater than 1:1
        deal(address(susde), address(almProxy), 100e18);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.usdeCooldownRateLimitKey(),
            100e18,
            uint256(100e18) / 1 hours
        );
        vm.stopPrank();

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(100e18);

        skip(7 days - 1);  // Cooldown period boundary

        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        vm.prank(allocator);
        mainnetController.unstakeSUSDe();

        skip(1 seconds);

        vm.prank(allocator);
        mainnetController.unstakeSUSDe();
    }

    function test_unstakeSUSDE() external {
        // Setting higher rate limit so shares can be used for cooldown
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.usdeCooldownRateLimitKey(),
            1000e18,
            uint256(1000e18) / 1 hours
        );
        vm.stopPrank();

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        deal(address(susde), address(almProxy), 100e18);

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDECooldownShares(100e18, assets);

        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(100e18);

        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),              startingSiloBalance + assets);

        skip(7 days);  // Cooldown period

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit IUSDEFacet.USDEUnstake(assets);

        vm.prank(allocator);
        mainnetController.unstakeSUSDe();

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usde.balanceOf(address(almProxy)), assets);
        assertEq(usde.balanceOf(silo),              startingSiloBalance);
    }

}

contract MainnetController_Ethena_E2ETests is Ethena_TestBase {

    address internal signer = makeAddr("signer");

    bytes32 internal burnKey;
    bytes32 internal cooldownKey;
    bytes32 internal depositKey;
    bytes32 internal mintKey;

    function setUp() public override {
        super.setUp();

        vm.startPrank(SPARK_PROXY);

        burnKey     = mainnetController.usdeBurnRateLimitKey();
        cooldownKey = mainnetController.usdeCooldownRateLimitKey();
        depositKey  = mainnetController.getERC4626DepositRateLimitKey(address(susde), Ethereum.USDE);
        mintKey     = mainnetController.usdeMintRateLimitKey();

        rateLimits.setRateLimitData(burnKey,     5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(cooldownKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(mintKey,     5_000_000e6,  uint256(1_000_000e6)  / 4 hours);

        mainnetController.setMaxExchangeRate(address(susde), susde.convertToShares(1e18), 1.2e18);

        vm.stopPrank();
    }

    // NOTE: In reality this is performed by the signer submitting an order with an EIP712 signature
    //       which is verified by the ethenaMinter contract, minting USDe into the ALMProxy.
    //       Also, for the purposes of this test, minting is done 1:1 with USDC.
    function _simulateUSDEMint(uint256 amount) internal {
        vm.prank(ETHENA_MINTER);
        usdc.transferFrom(address(almProxy), ETHENA_MINTER, amount);
        deal(address(usde), address(almProxy), amount * 1e12);
    }

    // NOTE: In reality this is performed by the signer submitting an order with an EIP712 signature
    //       which is verified by the ethenaMinter contract, minting USDe into the ALMProxy.
    //       Also, for the purposes of this test, minting is done 1:1 with USDC.
    function _simulateUSDEBurn(uint256 amount) internal {
        vm.prank(ETHENA_MINTER);
        usde.transferFrom(address(almProxy), ETHENA_MINTER, amount);
        deal(address(usdc), address(almProxy), amount / 1e12);
    }

    function test_ethena_e2eFlowUsingAssets() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        uint256 startingMinterBalance = usdc.balanceOf(ETHENA_MINTER);  // From mainnet state

        // Step 1: Mint USDe

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e6);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usde.balanceOf(address(almProxy)), 0);

        _simulateUSDEMint(1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance + 1_000_000e6);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18);

        // Step 2: Convert half of assets to sUSDe

        uint256 startingAssets = usde.balanceOf(address(susde));

        assertEq(usde.allowance(address(almProxy), address(susde)), 0);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(address(susde)),    startingAssets);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.depositERC4626(address(susde), 500_000e18, 0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 4_500_000e18);

        assertEq(usde.allowance(address(almProxy), address(susde)), 0);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 500_000e18 - 1);  // Rounding

        assertEq(usde.balanceOf(address(susde)),    startingAssets + 500_000e18);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        // Step 3: Cooldown sUSDe

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 500_000e18 - 1);  // Rounding

        assertEq(usde.balanceOf(silo), startingSiloBalance);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(500_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 4_500_000e18 + 1);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(silo), startingSiloBalance + 500_000e18 - 1);

        // Step 4: Wait for cooldown window to pass then unstake sUSDe

        skip(7 days);

        assertEq(usde.balanceOf(silo),              startingSiloBalance + 500_000e18 - 1);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        vm.prank(allocator);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(silo),              startingSiloBalance);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);

        // Step 5: Redeem USDe for USDC

        startingMinterBalance = usde.balanceOf(ETHENA_MINTER);  // From mainnet state

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(1_000_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_000_000e18 + 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e18 - 1);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);

        _simulateUSDEBurn(1_000_000e18 - 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 0);

        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance + 1_000_000e18 - 1);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6 - 1);  // Rounding
    }

    function test_ethena_e2eFlowUsingShares() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        uint256 startingMinterBalance = usdc.balanceOf(ETHENA_MINTER);  // From mainnet state

        // Step 1: Mint USDe

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e6);

        vm.prank(allocator);
        mainnetController.prepareUSDeMint(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usde.balanceOf(address(almProxy)), 0);

        _simulateUSDEMint(1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance + 1_000_000e6);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18);

        // Step 2: Convert half of assets to sUSDe

        uint256 startingAssets = usde.balanceOf(address(susde));

        assertEq(usde.allowance(address(almProxy), address(susde)), 0);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(address(susde)),    startingAssets);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 5_000_000e18);

        vm.prank(allocator);
        uint256 susdeShares = mainnetController.depositERC4626(address(susde), 500_000e18, 0);

        assertEq(rateLimits.getCurrentRateLimit(depositKey), 4_500_000e18);

        assertEq(susde.balanceOf(address(almProxy)), susdeShares);

        assertEq(usde.allowance(address(almProxy), address(susde)), 0);

        assertEq(susde.convertToAssets(susdeShares), 500_000e18 - 1);  // Rounding

        assertEq(usde.balanceOf(address(susde)),    startingAssets + 500_000e18);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        // Step 3: Cooldown sUSDe

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 500_000e18 - 1);  // Rounding

        assertEq(usde.balanceOf(silo), startingSiloBalance);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(susdeShares);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 4_500_000e18 + 1);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(silo), startingSiloBalance + 500_000e18 - 1);

        // Step 4: Wait for cooldown window to pass then unstake sUSDe

        skip(7 days);

        assertEq(usde.balanceOf(silo),              startingSiloBalance + 500_000e18 - 1);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        vm.prank(allocator);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(silo),              startingSiloBalance);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);

        // Step 5: Redeem USDe for USDC

        startingMinterBalance = usde.balanceOf(ETHENA_MINTER);  // From mainnet state

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.prepareUSDeBurn(1_000_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_000_000e18 + 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e18 - 1);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);

        _simulateUSDEBurn(1_000_000e18 - 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 0);

        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance + 1_000_000e18 - 1);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6 - 1);  // Rounding
    }

    function test_e2e_cooldownSharesAndAssets_sameRateLimit() external {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 5_000_000e18);

        vm.prank(allocator);
        mainnetController.cooldownAssetsSUSDe(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18 + (1_000_000e18 - 6400));  // Rounding

        vm.prank(allocator);
        mainnetController.cooldownSharesSUSDe(600_000e18);

        uint256 assets2 = susde.convertToAssets(600_000e18);

        assertGe(assets2, 600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18 + (1_000_000e18 - 6400) - assets2);
    }

}
