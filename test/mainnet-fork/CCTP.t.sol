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

import { makeUint32Key } from "../../src/libraries/RateLimitHelpers.sol";

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

    uint256 internal constant CCTP_MAX_FEE_CAP = 100e6;

    function setUp() public override {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setCCTPMaxFeeCap(CCTP_MAX_FEE_CAP);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23700802; // November 1, 2025
    }

}

contract MainnetController_CCTP_Transfer_Tests is MainnetController_CCTP_TestBase {

    function test_transferUSDCToCCTP_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountDomain() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountCCTP() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_cctpRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so second modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        mainnetController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_domainRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so first modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        mainnetController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPFacet/domain-not-configured");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
    }

}

contract MainnetController_CCTP_TransferWithFee_Tests is MainnetController_CCTP_TestBase {

    uint256 internal constant MAX_FEE = 10;

    function test_transferUSDCToCCTPWithFee_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferUSDCToCCTPWithFee(1e6, MAX_FEE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTPWithFee_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.transferUSDCToCCTPWithFee(1e6, MAX_FEE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTPWithFee_zeroMaxAmountDomain() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(1e6, MAX_FEE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTPWithFee_zeroMaxAmountCCTP() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(1e6, MAX_FEE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTPWithFee_cctpRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so second modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        mainnetController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            10_000_000e6 + 1,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            10_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );
    }

    function test_transferUSDCToCCTPWithFee_domainRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so first modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        mainnetController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            10_000_000e6 + 1,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            10_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );
    }

    function test_transferUSDCToCCTPWithFee_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPFacet/domain-not-configured");

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
        );
    }

    function test_transferUSDCToCCTPWithFee_maxFeeExceedsCapBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 1000e6);

        vm.expectRevert("CCTPFacet/max-fee-exceeds-cap");

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            1000e6,
            CCTP_MAX_FEE_CAP + 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            1000e6,
            CCTP_MAX_FEE_CAP,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );
    }

    function test_transferUSDCToCCTPWithFee_incorrectMaxFeeBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        vm.expectRevert("CCTPFacet/incorrect-max-fee");

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            1e6,
            1e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            1e6,
            1e6 - 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );
    }

}

// TODO: Figure out finalized structure for this repo/testing structure wise
abstract contract BaseChain_CCTP_TestBase is ForkTestBase {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    IERC20Like internal constant BASE_USDC = IERC20Like(Base.USDC);

    address internal constant BASE_CCTP_TOKEN_MESSENGER = Base.CCTP_TOKEN_MESSENGER;

    uint256 internal constant CCTP_MAX_FEE_CAP = 100e6;

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

        foreignAccessControls.grantRole(foreignAccessControls.FREEZER_ROLE(), freezer);
        foreignAccessControls.grantRole(foreignAccessControls.RELAYER_ROLE(), relayer);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "CCTP_FACET";

        foreignController.updateIntegrations(integrationIds);

        // Governance setting up parameters.

        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(address(almProxy))))
        );

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;

        bytes32 domainKeyEthereum = makeUint32Key(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), usdcMaxAmount, usdcSlope);
        foreignRateLimits.setRateLimitData(domainKeyEthereum,                      usdcMaxAmount, usdcSlope);

        foreignController.setCCTPMaxFeeCap(CCTP_MAX_FEE_CAP);

        vm.stopPrank();

        baseUSDCTotalSupply = BASE_USDC.totalSupply();

        source.selectFork();

        bridge = CCTPv2BridgeTesting.createCircleBridge(source, destination);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(address(foreignAlmProxy))))
        );
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23700802; // November 1, 2025
    }

    function _setControllerEntered() internal override {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _wireForeignCCTPFacet() internal {
        address cctpFacet = address(new CCTPFacet(BASE_CCTP_TOKEN_MESSENGER, Base.USDC));

        vm.label(cctpFacet, "CCTPFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setCCTPMaxFeeCap.selector,
            ICCTPFacet.setMaxFeeCap.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setCCTPMintRecipient.selector,
            ICCTPFacet.setMintRecipient.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getCCTPMaxFeeCap.selector,
            ICCTPFacet.maxFeeCap.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getCCTPMintRecipient.selector,
            ICCTPFacet.getMintRecipient.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.transferUSDCToCCTP.selector,
            ICCTPFacet.transfer.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.transferUSDCToCCTPWithFee.selector,
            ICCTPFacet.transferWithFee.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.LIMIT_USDC_TO_CCTP.selector,
            ICCTPFacet.LIMIT_TO_CCTP.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.LIMIT_USDC_TO_DOMAIN.selector,
            ICCTPFacet.LIMIT_TO_DOMAIN.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : cctpFacet,
            wires : wires
        });

        foreignBeacon.setIntegration("CCTP_FACET", config);
    }

}

contract ForeignController_CCTP_Transfer_Tests is BaseChain_CCTP_TestBase {

    using DomainHelpers for *;

    function setUp() public override {
        super.setUp();
        destination.selectFork();
    }

    function test_transferUSDCToCCTP_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountDomain() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountCCTP() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_cctpRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so second modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        foreignController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_domainRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so first modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        foreignController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignRateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPFacet/domain-not-configured");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
    }

}

contract ForeignController_CCTP_TransferWithFee_Tests is BaseChain_CCTP_TestBase {

    using DomainHelpers for *;

    uint256 internal constant MAX_FEE = 10;

    function setUp() public override {
        super.setUp();
        destination.selectFork();
    }

    function test_transferUSDCToCCTPWithFee_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);

        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));

        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_zeroMaxAmountDomain() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_zeroMaxAmountCCTP() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_cctpRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so second modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        foreignController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            10_000_000e6 + 1,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            10_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_domainRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so first modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        foreignController.setCCTPMintRecipient(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            10_000_000e6 + 1,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            10_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignRateLimits.setUnlimitedRateLimitData(
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPFacet/domain-not-configured");
        vm.prank(relayer);

        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
        );
    }

    function test_transferUSDCToCCTPWithFee_maxFeeExceedsCapBoundary() external {
        deal(Base.USDC, address(foreignAlmProxy), 1000e6);

        vm.expectRevert("CCTPFacet/max-fee-exceeds-cap");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1000e6,
            CCTP_MAX_FEE_CAP + 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1000e6,
            CCTP_MAX_FEE_CAP,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
    }

    function test_transferUSDCToCCTPWithFee_incorrectMaxFeeBoundary() external {
        deal(Base.USDC, address(foreignAlmProxy), 1e6);

        vm.expectRevert("CCTPFacet/incorrect-max-fee");

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            1e6,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            1e6 - 1,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );
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

        _expectEthereumCCTPEmit(114_803, 1e6);

        vm.record();

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

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

        // Will split into 3 separate transactions at max 1m each
        _expectEthereumCCTPEmit(114_803, 1_000_000e6);
        _expectEthereumCCTPEmit(114_804, 1_000_000e6);
        _expectEthereumCCTPEmit(114_805, 900_000e6);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(2_900_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

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
        bytes32 key = mainnetController.LIMIT_USDC_TO_CCTP();
        deal(Ethereum.USDC, address(almProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(USDC.balanceOf(address(almProxy)),   9_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        mainnetController.transferUSDCToCCTP(2_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(USDC.balanceOf(address(almProxy)),   7_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferUSDCToCCTP(3_000_001e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        mainnetController.transferUSDCToCCTP(3_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(4 hours);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 999_999.9936e6);

        mainnetController.transferUSDCToCCTP(999_999.9936e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

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

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        _expectBaseCCTPEmit(296_114, 1e6);

        vm.record();

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 1e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

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

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        // Will split into three separate transactions at max 1m each
        _expectBaseCCTPEmit(296_114, 1_000_000e6);
        _expectBaseCCTPEmit(296_115, 1_000_000e6);
        _expectBaseCCTPEmit(296_116, 600_000e6);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(2_600_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 2_600_000e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

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

        bytes32 key = foreignController.LIMIT_USDC_TO_CCTP();
        deal(Base.USDC, address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 9_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    5_000_000e6);

        foreignController.transferUSDCToCCTP(2_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 7_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferUSDCToCCTP(3_000_001e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        foreignController.transferUSDCToCCTP(3_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        skip(4 hours);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    999_999.9936e6);

        foreignController.transferUSDCToCCTP(999_999.9936e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        vm.stopPrank();
    }

    function _expectEthereumCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(CCTP_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Ethereum.USDC,
            amount                    : amount,
            depositor                 : address(almProxy),
            mintRecipient             : mainnetController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            destinationDomain         : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            destinationTokenMessenger : bytes32(0x00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d),
            destinationCaller         : bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            maxFee                    : 0,
            minFinalityThreshold      : 2_000,
            hookData                  : ""
        });

        vm.expectEmit(address(mainnetController));
        emit ICCTPFacet.CCTPTransferInitiated(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE,
            mainnetController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            amount
        );
    }

    function _expectBaseCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(BASE_CCTP_TOKEN_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Base.USDC,
            amount                    : amount,
            depositor                 : address(foreignAlmProxy),
            mintRecipient             : foreignController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            destinationDomain         : CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            destinationTokenMessenger : bytes32(0x00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d),
            destinationCaller         : bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            maxFee                    : 0,
            minFinalityThreshold      : 2_000,
            hookData                  : ""
        });

        vm.expectEmit(address(foreignController));
        emit ICCTPFacet.CCTPTransferInitiated(
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            foreignController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            amount
        );
    }

}

contract CCTP_TransferWithFee_IntegrationTests is BaseChain_CCTP_TestBase {

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    // NOTE : Max fee can be set any value now and the tests still passes as of now CCTPv2 fee is not enabled.
    //        When CCTP v2 enabled fee, the fee deduction assertions needs to be added.
    uint256 internal constant MAX_FEE = 0;

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    function test_transferUSDCToCCTPWithFee_sourceToDestination() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        _expectEthereumCCTPEmit(114_803, 1e6, MAX_FEE);

        vm.record();

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(1e6, MAX_FEE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE);

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

    function test_transferUSDCToCCTPWithFee_sourceToDestination_bigTransfer() external {
        deal(Ethereum.USDC, address(almProxy), 2_900_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),          2_900_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        // Will split into 3 separate transactions at max 1m each.
        // Same maxFee is used for each transaction, which is inaccurate but its fine since final deducted fee is not maxFee.
        _expectEthereumCCTPEmit(114_803, 1_000_000e6, MAX_FEE);
        _expectEthereumCCTPEmit(114_804, 1_000_000e6, MAX_FEE);
        _expectEthereumCCTPEmit(114_805, 900_000e6,   MAX_FEE);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTPWithFee(
            2_900_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
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

    function test_transferUSDCToCCTPWithFee_sourceToDestination_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDC_TO_CCTP();
        deal(Ethereum.USDC, address(almProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(USDC.balanceOf(address(almProxy)),   9_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        mainnetController.transferUSDCToCCTPWithFee(
            2_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        assertEq(USDC.balanceOf(address(almProxy)),   7_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferUSDCToCCTPWithFee(
            3_000_001e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        mainnetController.transferUSDCToCCTPWithFee(
            3_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(4 hours);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 999_999.9936e6);

        mainnetController.transferUSDCToCCTPWithFee(
            999_999.9936e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE
        );

        assertEq(USDC.balanceOf(address(almProxy)),   3_000_000.0064e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.stopPrank();
    }

    function test_transferUSDCToCCTPWithFee_destinationToSource() external {
        destination.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 1e6);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   1e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        _expectBaseCCTPEmit(296_114, 1e6, MAX_FEE);

        vm.record();

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            1e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 1e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        source.selectFork();

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        bridge.relayMessagesToSource(true);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY + 1e6);
    }

    function test_transferUSDCToCCTPWithFee_destinationToSource_bigTransfer() external {
        destination.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 2_600_000e6);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   2_600_000e6);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        // Will split into three separate transactions at max 1m each
        // Same maxFee is used for each transaction, which is inaccurate but its fine since final deducted fee is not maxFee.
        _expectBaseCCTPEmit(296_114, 1_000_000e6, MAX_FEE);
        _expectBaseCCTPEmit(296_115, 1_000_000e6, MAX_FEE);
        _expectBaseCCTPEmit(296_116, 600_000e6,   MAX_FEE);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTPWithFee(
            2_600_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(BASE_USDC.balanceOf(address(foreignController)), 0);
        assertEq(BASE_USDC.totalSupply(),                         baseUSDCTotalSupply - 2_600_000e6);

        assertEq(BASE_USDC.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER), 0);

        source.selectFork();

        assertEq(USDC.balanceOf(address(almProxy)),          0);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        bridge.relayMessagesToSource(true);

        assertEq(USDC.balanceOf(address(almProxy)),          2_600_000e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY + 2_600_000e6);
    }

    function test_transferUSDCToCCTPWithFee_destinationToSource_rateLimited() external {
        destination.selectFork();

        bytes32 key = foreignController.LIMIT_USDC_TO_CCTP();
        deal(Base.USDC, address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 9_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    5_000_000e6);

        foreignController.transferUSDCToCCTPWithFee(
            2_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 7_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferUSDCToCCTPWithFee(
            3_000_001e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        foreignController.transferUSDCToCCTPWithFee(
            3_000_000e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        skip(4 hours);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    999_999.9936e6);

        foreignController.transferUSDCToCCTPWithFee(
            999_999.9936e6,
            MAX_FEE,
            CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),    0);

        vm.stopPrank();
    }

    function _expectEthereumCCTPEmit(uint64 nonce, uint256 amount, uint256 maxFee) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(CCTP_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Ethereum.USDC,
            amount                    : amount,
            depositor                 : address(almProxy),
            mintRecipient             : mainnetController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
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
            mainnetController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE),
            amount
        );
    }

    function _expectBaseCCTPEmit(uint64 nonce, uint256 amount, uint256 maxFee) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(BASE_CCTP_TOKEN_MESSENGER);
        emit ICCTPLike.DepositForBurn({
            burnToken                 : Base.USDC,
            amount                    : amount,
            depositor                 : address(foreignAlmProxy),
            mintRecipient             : foreignController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
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
            foreignController.getCCTPMintRecipient(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            amount
        );
    }

}
