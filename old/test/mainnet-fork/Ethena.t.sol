// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IEthenaMinterLike {
    function delegatedSigner(address signer, address owner) external view returns (uint8);
}

contract EthenaTestBase is ForkTestBase {

    function _getBlock() internal pure override returns (uint256) {
        return 21417200;  // Dec 16, 2024
    }
}

contract MainnetControllerSetDelegatedSignerFailureTests is EthenaTestBase {

    function test_setDelegatedSigner_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.setDelegatedSigner(makeAddr("signer"));
    }

}

contract MainnetControllerSetDelegatedSignerSuccessTests is EthenaTestBase {

    event DelegatedSignerInitiated(address indexed delegateTo, address indexed initiatedBy);

    function test_setDelegatedSigner() external {
        address signer = makeAddr("signer");

        IEthenaMinterLike ethenaMinter = IEthenaMinterLike(ETHENA_MINTER);

        assertEq(ethenaMinter.delegatedSigner(signer, address(almProxy)), 0);  // REJECTED

        vm.prank(relayer);
        vm.expectEmit(ETHENA_MINTER);
        emit DelegatedSignerInitiated(signer, address(almProxy));
        mainnetController.setDelegatedSigner(signer);

        assertEq(ethenaMinter.delegatedSigner(signer, address(almProxy)), 1);  // PENDING
    }

}

contract MainnetControllerRemoveDelegatedSignerFailureTests is EthenaTestBase {

    function test_removeDelegatedSigner_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.removeDelegatedSigner(makeAddr("signer"));
    }

}

contract MainnetControllerRemoveDelegatedSignerSuccessTests is EthenaTestBase {

    event DelegatedSignerRemoved(address indexed removedSigner, address indexed initiatedBy);

    function test_removeDelegatedSigner() external {
        address signer = makeAddr("signer");

        IEthenaMinterLike ethenaMinter = IEthenaMinterLike(ETHENA_MINTER);

        vm.prank(relayer);
        mainnetController.setDelegatedSigner(signer);

        assertEq(ethenaMinter.delegatedSigner(signer, address(almProxy)), 1);  // PENDING

        vm.prank(relayer);
        vm.expectEmit(ETHENA_MINTER);
        emit DelegatedSignerRemoved(signer, address(almProxy));
        mainnetController.removeDelegatedSigner(signer);

        assertEq(ethenaMinter.delegatedSigner(signer, address(almProxy)), 0);  // REJECTED
    }

}

contract MainnetControllerPrepareUSDeMintFailureTests is EthenaTestBase {

    function test_prepareUSDeMint_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.prepareUSDeMint(100);
    }

    function test_prepareUSDeMint_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDE_MINT(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.prepareUSDeMint(1e18);
    }

    function test_prepareUSDeMint_rateLimitBoundary() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_USDE_MINT(),
            100e6,
            uint256(100e6) / 1 hours
        );
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.prepareUSDeMint(100e6 + 1);

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(100e6);
    }

}

contract MainnetControllerPrepareUSDeMintSuccessTests is EthenaTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.LIMIT_USDE_MINT();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e6, uint256(1_000_000e6) / 4 hours);
    }

    function test_prepareUSDeMint() external {
        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 0);

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(100e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 100e6);
    }

    function test_prepareUSDeMint_rateLimits() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(4_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e6 - 6400);  // Rounding

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(600_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e6 - 6400);  // Rounding
    }

}

contract MainnetControllerPrepareUSDeBurnFailureTests is EthenaTestBase {

    function test_prepareUSDeBurn_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.prepareUSDeBurn(100);
    }

    function test_prepareUSDeBurn_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDE_BURN(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.prepareUSDeBurn(1e18);
    }

    function test_prepareUSDeBurn_rateLimitBoundary() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_USDE_BURN(),
            100e18,
            uint256(100e18) / 1 hours
        );
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.prepareUSDeBurn(100e18 + 1);

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(100e18);
    }

}

contract MainnetControllerPrepareUSDeBurnSuccessTests is EthenaTestBase {

    bytes32 key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.LIMIT_USDE_BURN();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_prepareUSDeBurn() external {
        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 0);

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(100e18);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 100e18);
    }

    function test_prepareUSDeBurn_rateLimits() external {
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e18 - 6400);  // Rounding

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e18 - 6400);  // Rounding
    }

}

contract MainnetControllerCooldownAssetsSUSDeFailureTests is EthenaTestBase {

    function test_cooldownAssetsSUSDe_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDe_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_SUSDE_COOLDOWN(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

    function test_cooldownAssetsSUSDe_rateLimitBoundary() external {
        // For success case (exchange rate is more than 1:1)
        deal(address(susde), address(almProxy), 100e18);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_SUSDE_COOLDOWN(),
            100e18,
            uint256(100e18) / 1 hours
        );
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.cooldownAssetsSUSDe(100e18 + 1);

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(100e18);
    }

}

contract MainnetControllerCooldownAssetsSUSDeSuccessTests is EthenaTestBase {

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    bytes32 key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.LIMIT_SUSDE_COOLDOWN();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_cooldownAssetsSUSDe() external {
        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 100e18);

        assertEq(susde.balanceOf(address(almProxy)), 100e18);
        assertEq(usde.balanceOf(silo),               startingSiloBalance);

        vm.prank(relayer);
        vm.expectEmit(address(susde));
        emit Withdraw(address(almProxy), silo, address(almProxy), assets, 100e18);
        mainnetController.cooldownAssetsSUSDe(assets);

        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),               startingSiloBalance + assets);
    }

    function test_cooldownAssetsSUSDe_rateLimits() external {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 2_000_000e18 - 6400);  // Rounding

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_400_000e18 - 6400);  // Rounding
    }

}

contract MainnetControllerCooldownSharesSUSDeFailureTests is EthenaTestBase {

    function test_cooldownSharesSUSDe_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.cooldownSharesSUSDe(100);
    }

    function test_cooldownSharesSUSDe_zeroMaxAmount() external {
        deal(address(susde), address(almProxy), 100e18);  // To get past call

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_SUSDE_COOLDOWN(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.cooldownSharesSUSDe(100e18);
    }

    function test_cooldownSharesSUSDe_rateLimitBoundary() external {
        deal(address(susde), address(almProxy), 100e18);  // For success case

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_SUSDE_COOLDOWN(),
            100e18,
            uint256(100e18) / 1 hours
        );
        vm.stopPrank();

        uint256 overBoundaryShares = susde.convertToShares(100e18 + 2);
        uint256 boundaryShares     = susde.convertToShares(100e18 + 1);

        // Demonstrate how rounding works
        assertEq(susde.previewRedeem(overBoundaryShares), 100e18 + 1);
        assertEq(susde.previewRedeem(boundaryShares),     100e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.cooldownSharesSUSDe(overBoundaryShares);

        vm.prank(relayer);
        mainnetController.cooldownSharesSUSDe(boundaryShares);
    }

}

contract MainnetControllerCooldownSharesSUSDeSuccessTests is EthenaTestBase {

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    bytes32 key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.LIMIT_SUSDE_COOLDOWN();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
    }

    function test_cooldownSharesSUSDe() external {
        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        deal(address(susde), address(almProxy), 100e18);

        assertEq(susde.balanceOf(address(almProxy)), 100e18);
        assertEq(usde.balanceOf(silo),               startingSiloBalance);

        vm.prank(relayer);
        vm.expectEmit(address(susde));
        emit Withdraw(address(almProxy), silo, address(almProxy), assets, 100e18);
        uint256 returnedAssets = mainnetController.cooldownSharesSUSDe(100e18);

        assertEq(returnedAssets, assets);

        assertEq(susde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),               startingSiloBalance + assets);
    }

    function test_cooldownSharesSUSDe_rateLimits() external {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18);

        vm.prank(relayer);
        uint256 returnedAssets = mainnetController.cooldownSharesSUSDe(4_000_000e18);

        uint256 assets1 = susde.convertToAssets(4_000_000e18);

        assertEq(returnedAssets, assets1);

        assertGe(assets1, 4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1 + (1_000_000e18 - 6400));  // Rounding

        vm.prank(relayer);
        returnedAssets = mainnetController.cooldownSharesSUSDe(600_000e18);

        uint256 assets2 = susde.convertToAssets(600_000e18);

        assertEq(returnedAssets, assets2);

        assertGe(assets2, 600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e18 - assets1 + (1_000_000e18 - 6400) - assets2);
    }

}

contract MainnetControllerUnstakeSUSDeFailureTests is EthenaTestBase {

    function test_unstakeSUSDe_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.unstakeSUSDe();
    }

    function test_unstakeSUSDe_cooldownBoundary() external {
        // Exchange rate greater than 1:1
        deal(address(susde), address(almProxy), 100e18);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_SUSDE_COOLDOWN(),
            100e18,
            uint256(100e18) / 1 hours
        );
        vm.stopPrank();

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(100e18);

        skip(7 days - 1);  // Cooldown period boundary

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        mainnetController.unstakeSUSDe();

        skip(1 seconds);

        vm.prank(relayer);
        mainnetController.unstakeSUSDe();
    }

}

contract MainnetControllerUnstakeSUSDeSuccessTests is EthenaTestBase {

    function test_unstakeSUSDe() external {
        // Setting higher rate limit so shares can be used for cooldown
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_SUSDE_COOLDOWN(),
            1000e18,
            uint256(1000e18) / 1 hours
        );
        vm.stopPrank();

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        uint256 assets = susde.convertToAssets(100e18);

        deal(address(susde), address(almProxy), 100e18);

        vm.prank(relayer);
        mainnetController.cooldownSharesSUSDe(100e18);

        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),              startingSiloBalance + assets);

        skip(7 days);  // Cooldown period

        vm.prank(relayer);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(address(almProxy)), assets);
        assertEq(usde.balanceOf(silo),              startingSiloBalance);
    }

}

contract MainnetControllerEthenaE2ETests is EthenaTestBase {

    address signer = makeAddr("signer");

    bytes32 burnKey;
    bytes32 cooldownKey;
    bytes32 depositKey;
    bytes32 mintKey;

    function setUp() public override {
        super.setUp();

        vm.startPrank(SPARK_PROXY);

        burnKey     = mainnetController.LIMIT_USDE_BURN();
        cooldownKey = mainnetController.LIMIT_SUSDE_COOLDOWN();
        depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), address(susde));
        mintKey     = mainnetController.LIMIT_USDE_MINT();

        rateLimits.setRateLimitData(burnKey,     5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(cooldownKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(mintKey,     5_000_000e6,  uint256(1_000_000e6)  / 4 hours);

        mainnetController.setMaxSlippage(address(susde), 1e18 - 1e4);  // Rounding slippage

        vm.stopPrank();
    }

    // NOTE: In reality this is performed by the signer submitting an order with an EIP712 signature
    //       which is verified by the ethenaMinter contract, minting USDe into the ALMProxy.
    //       Also, for the purposes of this test, minting is done 1:1 with USDC.
    function _simulateUsdeMint(uint256 amount) internal {
        vm.prank(ETHENA_MINTER);
        usdc.transferFrom(address(almProxy), ETHENA_MINTER, amount);
        deal(address(usde), address(almProxy), amount * 1e12);
    }

    // NOTE: In reality this is performed by the signer submitting an order with an EIP712 signature
    //       which is verified by the ethenaMinter contract, minting USDe into the ALMProxy.
    //       Also, for the purposes of this test, minting is done 1:1 with USDC.
    function _simulateUsdeBurn(uint256 amount) internal {
        vm.prank(ETHENA_MINTER);
        usde.transferFrom(address(almProxy), ETHENA_MINTER, amount);
        deal(address(usdc), address(almProxy), amount / 1e12);
    }

    function test_ethena_e2eFlowUsingAssets() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        uint256 startingMinterBalance = usdc.balanceOf(ETHENA_MINTER);  // From mainnet state

        // Step 1: Mint USDe

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 5_000_000e6);

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usde.balanceOf(address(almProxy)), 0);

        _simulateUsdeMint(1_000_000e6);

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

        vm.prank(relayer);
        mainnetController.depositERC4626(address(susde), 500_000e18);

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

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(500_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 4_500_000e18 + 1);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(silo), startingSiloBalance + 500_000e18 - 1);

        // Step 4: Wait for cooldown window to pass then unstake sUSDe

        skip(7 days);

        assertEq(usde.balanceOf(silo),              startingSiloBalance + 500_000e18 - 1);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        vm.prank(relayer);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(silo),              startingSiloBalance);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);

        // Step 5: Redeem USDe for USDC

        startingMinterBalance = usde.balanceOf(ETHENA_MINTER);  // From mainnet state

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(1_000_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_000_000e18 + 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e18 - 1);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);

        _simulateUsdeBurn(1_000_000e18 - 1);

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

        vm.prank(relayer);
        mainnetController.prepareUSDeMint(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(mintKey), 4_000_000e6);

        assertEq(usdc.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usde.balanceOf(address(almProxy)), 0);

        _simulateUsdeMint(1_000_000e6);

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

        vm.prank(relayer);
        uint256 susdeShares = mainnetController.depositERC4626(address(susde), 500_000e18);

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

        vm.prank(relayer);
        mainnetController.cooldownSharesSUSDe(susdeShares);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 4_500_000e18 + 1);

        assertEq(susde.convertToAssets(susde.balanceOf(address(almProxy))), 0);

        assertEq(usde.balanceOf(silo), startingSiloBalance + 500_000e18 - 1);

        // Step 4: Wait for cooldown window to pass then unstake sUSDe

        skip(7 days);

        assertEq(usde.balanceOf(silo),              startingSiloBalance + 500_000e18 - 1);
        assertEq(usde.balanceOf(address(almProxy)), 500_000e18);

        vm.prank(relayer);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(silo),              startingSiloBalance);
        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);

        // Step 5: Redeem USDe for USDC

        startingMinterBalance = usde.balanceOf(ETHENA_MINTER);  // From mainnet state

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 5_000_000e18);

        vm.prank(relayer);
        mainnetController.prepareUSDeBurn(1_000_000e18 - 1);

        assertEq(rateLimits.getCurrentRateLimit(burnKey), 4_000_000e18 + 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 1_000_000e18 - 1);

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 - 1);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance);

        assertEq(usdc.balanceOf(address(almProxy)), 0);

        _simulateUsdeBurn(1_000_000e18 - 1);

        assertEq(usde.allowance(address(almProxy), ETHENA_MINTER), 0);

        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(ETHENA_MINTER),     startingMinterBalance + 1_000_000e18 - 1);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6 - 1);  // Rounding
    }

    function test_e2e_cooldownSharesAndAssets_sameRateLimit() public {
        // Exchange rate is more than 1:1
        deal(address(susde), address(almProxy), 5_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 5_000_000e18);

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(4_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18 + (1_000_000e18 - 6400));  // Rounding

        vm.prank(relayer);
        mainnetController.cooldownSharesSUSDe(600_000e18);

        uint256 assets2 = susde.convertToAssets(600_000e18);

        assertGe(assets2, 600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(cooldownKey), 1_000_000e18 + (1_000_000e18 - 6400) - assets2);
    }

}
