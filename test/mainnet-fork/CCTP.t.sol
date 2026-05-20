// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { Base }     from "../../lib/spark-address-registry/src/Base.sol";

import { Bridge }                from "../../lib/grove-xchain-helpers/src/testing/Bridge.sol";
import { CCTPv2BridgeTesting }   from "../../lib/grove-xchain-helpers/src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }       from "../../lib/grove-xchain-helpers/src/forwarders/CCTPv2Forwarder.sol";
import { Domain, DomainHelpers } from "../../lib/grove-xchain-helpers/src/testing/Domain.sol";

import { CCTPFacet } from "../../src/facets/cctp/CCTPFacet.sol";

import { ICCTPFacet } from "../../src/facets/cctp/ICCTPFacet.sol";

import { IAccessControls }         from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }               from "../../src/interfaces/IALMProxy.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";
import { IRateLimits }             from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

import { IForeignControllerFull } from "../interfaces/IForeignControllerFull.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface ICCTPLike {

    event DepositForBurn(
        address indexed burnToken,
        uint256         amount,
        address indexed depositor,
        bytes32         mintRecipient,
        uint32          destinationDomain,
        bytes32         destinationTokenMessenger,
        bytes32         destinationCaller,
        uint256         maxFee,
        uint32  indexed minFinalityThreshold,
        bytes           hookData
    );

}

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

abstract contract MainnetController_CCTP_TestBase is ForkTestBase {

    function _getBlock() internal pure override returns (uint256) {
        return 23700802; // November 1, 2025
    }

}

contract MainnetController_CCTP_Transfer_Tests is MainnetController_CCTP_TestBase {

    bytes32 internal recipient = bytes32(uint256(uint160(makeAddr("recipient"))));

    function test_transferUSDCToCCTP_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.cctp_transfer(0, 0, 0);
    }

    function test_transferUSDCToCCTP_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.cctp_transfer(0, 0, 0);
    }

    function test_transferUSDCToCCTP_cctpRateLimitZeroMaxAmount() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.cctp_transfer(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE, 0);
    }

    function test_transferUSDCToCCTP_cctpRateLimitBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this for success case.
        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            0,
            0
        );

        rateLimits.setRateLimitData(mainnetController.cctp_toCCTPRateLimitKey(), 10_000_000e6, 0);

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE)
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            10_000_000e6 + 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            0
        );

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            10_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            0
        );
    }

    function test_transferUSDCToCCTP_domainRateLimitZeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.cctp_toCCTPRateLimitKey(), 1e6, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.cctp_transfer(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE, 0);
    }

    function test_transferUSDCToCCTP_domainRateLimitBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this for success case.
        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            0,
            0
        );

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(mainnetController.cctp_toCCTPRateLimitKey());

        rateLimits.setRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            10_000_000e6 + 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            0
        );

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            10_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            0
        );
    }

    function test_transferUSDCToCCTP_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so second modifier will be passed in success case.
        rateLimits.setUnlimitedRateLimitData(mainnetController.cctp_toCCTPRateLimitKey());

        // Set this so first modifier will be passed in success case.
        rateLimits.setUnlimitedRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE)
        );

        vm.stopPrank();

        vm.expectRevert("CCTPFacet/domain-not-configured");

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            0
        );
    }

    function test_transferUSDCToCCTP_feeCapRateTooLowBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this for success case.
        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            1_000,
            9_000
        );

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(mainnetController.cctp_toCCTPRateLimitKey());

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE)
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1000e6);

        vm.expectRevert("CCTPFacet/fee-cap-rate-too-low");

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            1_000 - 1
        );

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            1_000
        );
    }

    function test_transferUSDCToCCTP_feeCapRateTooHighBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this for success case.
        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            1_000,
            9_000
        );

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(mainnetController.cctp_toCCTPRateLimitKey());

        // Set this for success case.
        rateLimits.setUnlimitedRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE)
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 1000e6);

        vm.expectRevert("CCTPFacet/fee-cap-rate-too-high");

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            9_000 + 1
        );

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            9_000
        );
    }

    function test_transferUSDCToCCTP() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            0,
            100
        );

        rateLimits.setRateLimitData(
            mainnetController.cctp_toCCTPRateLimitKey(),
            10_000_000e6,
            0
        );

        rateLimits.setRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6);

        vm.expectEmit(address(mainnetController));
        emit ICCTPFacet.CCTPTransferInitiated(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            recipient,
            1_000e6,
            1e6
        );

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            1000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            10
        );
    }

}

abstract contract BaseChain_CCTP_TestBase is ForkTestBase {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    IERC20Like internal constant BASE_USDC = IERC20Like(Base.USDC);

    address internal skyAdmin = makeAddr("skyAdmin");

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    Beacon                 internal foreignBeacon;
    IALMProxy              internal foreignAlmProxy;
    IForeignControllerFull internal foreignController;
    IRateLimits            internal foreignRateLimits;

    /**********************************************************************************************/
    /*** Bridging setup                                                                         ***/
    /**********************************************************************************************/

    Bridge internal bridge;
    Domain internal source;
    Domain internal destination;

    uint256 internal baseUSDCTotalSupply;

    function setUp() public override virtual {
        super.setUp();

        // Reuse the same mainnet fork so contracts from ForkTestBase.setUp() are accessible
        source = Domain({
            chain  : getChain("mainnet"),
            forkId : vm.activeFork()
        });

        destination = getChain("base").createSelectFork(37589683);  // November 1, 2025

        // Deploy and configure ALM system

        foreignBeacon = new Beacon(skyAdmin);

        PAUFactory foreignFactory = new PAUFactory(address(foreignBeacon));

        foreignController = IForeignControllerFull(payable(foreignFactory.deploy(Base.SPARK_EXECUTOR)));
        foreignAlmProxy   = IALMProxy(payable(foreignController.proxy()));
        foreignRateLimits = IRateLimits(foreignController.rateLimits());

        IAccessControls foreignAccessControls = IAccessControls(foreignController.accessControls());

        vm.startPrank(skyAdmin);

        // Facet wiring
        _wireForeignCCTPFacet();

        vm.stopPrank();

        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignAccessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        foreignAccessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role 
        //       logic that calls into AccessControls to perform grants and revocations.
        foreignAccessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "CCTP_FACET";

        foreignController.updateIntegrations(integrationIds);

        // Governance setting up parameters.

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;

        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(address(almProxy)))),
            0,
            100
        );

        foreignRateLimits.setRateLimitData(foreignController.cctp_toCCTPRateLimitKey(), usdcMaxAmount, usdcSlope);

        foreignRateLimits.setRateLimitData(
            foreignController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            usdcMaxAmount,
            usdcSlope
        );

        vm.stopPrank();

        baseUSDCTotalSupply = BASE_USDC.totalSupply();

        source.selectFork();

        bridge = CCTPv2BridgeTesting.createCircleBridge(source, destination);

        vm.startPrank(Ethereum.SPARK_PROXY);

        mainnetController.cctp_setDomainParameters(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(address(foreignAlmProxy)))),
            0,
            100
        );

        rateLimits.setRateLimitData(mainnetController.cctp_toCCTPRateLimitKey(), usdcMaxAmount, usdcSlope);

        rateLimits.setRateLimitData(
            mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            usdcMaxAmount,
            usdcSlope
        );

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23700802; // November 1, 2025
    }

    function _setControllerEntered() internal override {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _wireForeignCCTPFacet() internal {
        address cctpFacet = address(new CCTPFacet(Base.CCTP_TOKEN_MESSENGER, Base.USDC));

        vm.label(cctpFacet, "CCTPFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.cctp_setDomainParameters.selector,
            ICCTPFacet.setDomainParameters.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.cctp_transfer.selector,
            ICCTPFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.cctp_toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.cctp_getDomainParameters.selector,
            ICCTPFacet.getDomainParameters.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.cctp_getToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : cctpFacet,
            wires : wires
        });

        foreignBeacon.setIntegration("CCTP_FACET", config);
    }

}

contract CCTP_Transfer_IntegrationTests is BaseChain_CCTP_TestBase {

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    function test_transferUSDCToCCTP_sourceToDestination() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        _expectEthereumCCTPEmit(114_803, 1e6, 100);

        vm.record();

        vm.prank(allocator);
        mainnetController.cctp_transfer(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE, 100);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY - 1e6);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        destination.selectFork();

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        bridge.relayMessagesToDestination(true);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   1e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply + 1e6);
    }

    function test_transferUSDCToCCTP_sourceToDestination_bigTransfer() external {
        deal(Ethereum.USDC, address(almProxy), 2_900_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),          2_900_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        // Will split into 3 separate transactions at max 1m each.
        // Same maxFee is used for each transaction, which is inaccurate but its fine since final deducted fee is not maxFee.
        _expectEthereumCCTPEmit(114_803, 1_000_000e6, 100);
        _expectEthereumCCTPEmit(114_804, 1_000_000e6, 100);
        _expectEthereumCCTPEmit(114_805, 900_000e6,   100);

        vm.prank(allocator);
        mainnetController.cctp_transfer(
            2_900_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            100
        );

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY - 2_900_000e6);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        destination.selectFork();

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        bridge.relayMessagesToDestination(true);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   2_900_000e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply + 2_900_000e6);
    }

    function test_transferUSDCToCCTP_sourceToDestination_rateLimited() external {
        bytes32 key = mainnetController.cctp_toCCTPRateLimitKey();
        deal(Ethereum.USDC, address(almProxy), 9_000_000e6);

        vm.startPrank(allocator);

        assertEq(USDC.balanceOf(address(almProxy)),   9_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        mainnetController.cctp_transfer(
            2_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            100
        );

        assertEq(USDC.balanceOf(address(almProxy)),   7_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.cctp_transfer(
            3_000_001e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            100
        );

        mainnetController.cctp_transfer(
            3_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            100
        );

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(4 hours);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 999_999.9936e6);

        mainnetController.cctp_transfer(
            999_999.9936e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            100
        );

        assertEq(USDC.balanceOf(address(almProxy)),   3_000_000.0064e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.stopPrank();
    }

    function test_transferUSDCToCCTP_destinationToSource() external {
        destination.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 1e6);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   1e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), Base.CCTP_TOKEN_MESSENGER), 0);

        _expectBaseCCTPEmit(296_114, 1e6, 100);

        vm.record();

        vm.prank(allocator);
        foreignController.cctp_transfer(
            1e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 1e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), Base.CCTP_TOKEN_MESSENGER), 0);

        source.selectFork();

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        bridge.relayMessagesToSource(true);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY + 1e6);
    }

    function test_transferUSDCToCCTP_destinationToSource_bigTransfer() external {
        destination.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 2_600_000e6);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   2_600_000e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), Base.CCTP_TOKEN_MESSENGER), 0);

        // Will split into three separate transactions at max 1m each
        // Same maxFee is used for each transaction, which is inaccurate but its fine since final deducted fee is not maxFee.
        _expectBaseCCTPEmit(296_114, 1_000_000e6, 100);
        _expectBaseCCTPEmit(296_115, 1_000_000e6, 100);
        _expectBaseCCTPEmit(296_116, 600_000e6,   100);

        vm.prank(allocator);
        foreignController.cctp_transfer(
            2_600_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 2_600_000e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), Base.CCTP_TOKEN_MESSENGER), 0);

        source.selectFork();

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        bridge.relayMessagesToSource(true);

        assertEq(USDC.balanceOf(address(almProxy)),          2_600_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY + 2_600_000e6);
    }

    function test_transferUSDCToCCTP_destinationToSource_rateLimited() external {
        destination.selectFork();

        bytes32 key = foreignController.cctp_toCCTPRateLimitKey();
        deal(Base.USDC, address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(allocator);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 9_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    5_000_000e6);

        foreignController.cctp_transfer(
            2_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 7_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.cctp_transfer(
            3_000_001e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        foreignController.cctp_transfer(
            3_000_000e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        skip(4 hours);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    999_999.9936e6);

        foreignController.cctp_transfer(
            999_999.9936e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            100
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        vm.stopPrank();
    }

    function _expectEthereumCCTPEmit(uint64 nonce, uint256 amount, uint256 maxFeeRate) internal {
        uint256 maxFee = amount * maxFeeRate / 10_000;

        ( bytes32 mintRecipient, , ) = mainnetController.cctp_getDomainParameters(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(CCTP_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Ethereum.USDC,
            amount                    : amount,
            depositor                 : address(almProxy),
            mintRecipient             : mintRecipient,
            destinationDomain         : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            destinationTokenMessenger : bytes32(0x00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d),
            destinationCaller         : bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            maxFee                    : maxFee,
            minFinalityThreshold      : 2_000,
            hookData                  : ""
        });

        vm.expectEmit(address(mainnetController));
        emit ICCTPFacet.CCTPTransferInitiated(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient,
            amount,
            maxFee
        );
    }

    function _expectBaseCCTPEmit(uint64 nonce, uint256 amount, uint256 maxFeeRate) internal {
        uint256 maxFee = amount * maxFeeRate / 10_000;

        ( bytes32 mintRecipient, , ) = foreignController.cctp_getDomainParameters(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(Base.CCTP_TOKEN_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Base.USDC,
            amount                    : amount,
            depositor                 : address(foreignAlmProxy),
            mintRecipient             : mintRecipient,
            destinationDomain         : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            destinationTokenMessenger : bytes32(0x00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d),
            destinationCaller         : bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            maxFee                    : maxFee,
            minFinalityThreshold      : 2_000,
            hookData                  : ""
        });

        vm.expectEmit(address(foreignController));
        emit ICCTPFacet.CCTPTransferInitiated(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient,
            amount,
            maxFee
        );
    }

}
