// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { Base }     from "../../lib/spark-address-registry/src/Base.sol";

import { Bridge }                from "../../lib/xchain-helpers/src/testing/Bridge.sol";
import { CCTPBridgeTesting }     from "../../lib/xchain-helpers/src/testing/bridges/CCTPBridgeTesting.sol";
import { CCTPForwarder  }        from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { CCTPV2BridgeTesting }   from "../../lib/xchain-helpers/src/testing/bridges/CCTPV2BridgeTesting.sol";
import { Domain, DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { ForeignControllerInit }   from "../../deploy/ForeignControllerInit.sol";

import { CCTPLib } from "../../src/libraries/CCTPLib.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimitHelpers }  from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface ICCTPv1Like {

    event DepositForBurn(
        uint64  indexed nonce,
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32  destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller
    );

}

interface ICCTPv2Like {

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

contract MainnetController_CCTP_Transfer_Tests is ForkTestBase {

    uint256 internal constant CCTP_MAX_FEE_RATE = 10;

    function setUp() public override {
        super.setUp();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setCCTPMaxFeeRate(CCTP_MAX_FEE_RATE);
    }

    function _getBlock() internal override pure returns (uint256) {
        return 26077600; // September 28, 2026
    }

    function test_transferUSDCToCCTP_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountDomain() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountCCTP() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_cctpRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so second modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_BASE
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        mainnetController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_domainRateLimitedBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);

        // Set this so first modifier will be passed in success case
        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_BASE
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        mainnetController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Ethereum.USDC, address(almProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(10_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
    }

    function test_transferUSDCToCCTP_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Ethereum.SPARK_PROXY);

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeUint32Key(
                mainnetController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPLib/domain-not-configured");
        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
    }

}

// TODO: Figure out finalized structure for this repo/testing structure wise
abstract contract BaseChain_CCTP_TestBase is ForkTestBase {

    using DomainHelpers for *;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address internal constant BASE_CCTP_TOKEN_MESSENGER_V1 = Base.CCTP_TOKEN_MESSENGER_V1;  // ForeignController stays on v1

    uint256 internal constant CCTP_MAX_FEE_CAP = 100e6;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy          internal foreignAlmProxy;
    RateLimits        internal foreignRateLimits;
    ForeignController internal foreignController;

    /**********************************************************************************************/
    /*** Bridging setup                                                                         ***/
    /**********************************************************************************************/

    Bridge internal ethBridge;
    Bridge internal baseBridge;
    Domain internal ethDomain;
    Domain internal baseDomain;

    IERC20Like internal usdcBase;

    uint256 internal baseUSDCTotalSupply;

    function setUp() public override virtual {
        super.setUp();

        // Reuse the same mainnet fork so contracts from ForkTestBase.setUp() are accessible
        ethDomain = Domain({
            chain  : getChain("mainnet"),
            forkId : vm.activeFork()
        });

        baseDomain = getChain("base").createSelectFork(51914000);  // September 28, 2026

        usdcBase = IERC20Like(Base.USDC);

        /*** Step 3: Deploy and configure ALM system ***/

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin : Base.SPARK_EXECUTOR,
            psm   : address(0),
            usdc  : Base.USDC,
            cctp  : BASE_CCTP_TOKEN_MESSENGER_V1
        });

        foreignAlmProxy   = ALMProxy(payable(controllerInst.almProxy));
        foreignRateLimits = RateLimits(controllerInst.rateLimits);
        foreignController = ForeignController(controllerInst.controller);

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;

        ForeignControllerInit.ConfigAddressParams memory configAddresses = ForeignControllerInit.ConfigAddressParams({
            freezer       : freezer,
            relayers      : relayers,
            oldController : address(0)
        });

        ForeignControllerInit.CheckAddressParams memory checkAddresses = ForeignControllerInit.CheckAddressParams({
            admin : Base.SPARK_EXECUTOR,
            psm   : address(0),
            cctp  : BASE_CCTP_TOKEN_MESSENGER_V1,
            usdc  : Base.USDC,
            susds : address(0),
            usds  : address(0)
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(address(almProxy))))
        });

        vm.startPrank(Base.SPARK_EXECUTOR);
        ForeignControllerInit.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients,
            new ForeignControllerInit.LayerZeroRecipient[](0),
            new ForeignControllerInit.MaxSlippageParams[](0),
            false
        );

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;

        bytes32 domainKeyEthereum = RateLimitHelpers.makeUint32Key(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), usdcMaxAmount, usdcSlope);
        foreignRateLimits.setRateLimitData(domainKeyEthereum,                      usdcMaxAmount, usdcSlope);

        vm.stopPrank();

        baseUSDCTotalSupply = usdcBase.totalSupply();

        ethDomain.selectFork();

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(address(foreignAlmProxy))))
        );

        ethBridge  = CCTPV2BridgeTesting.createCircleBridge(ethDomain, baseDomain);
        baseBridge = CCTPBridgeTesting.createCircleBridge(baseDomain, ethDomain);

        ethDomain.selectFork();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 26077600; // September 28, 2026
    }

    function _setControllerEntered() internal override {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

}

contract ForeignController_CCTP_Transfer_Tests is BaseChain_CCTP_TestBase {

    using DomainHelpers for *;

    function setUp( ) public override {
        super.setUp();
        baseDomain.selectFork();
    }

    function test_transferUSDCToCCTP_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountDomain() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_zeroMaxAmountCCTP() external {
        vm.startPrank(Base.SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 0, 0);
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_cctpRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so second modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            )
        );

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), 10_000_000e6, 0);

        // Set this for success case
        foreignController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_domainRateLimitedBoundary() external {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Set this so first modifier will be passed in success case
        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        // Rate limit will be constant 10m (higher than setup)
        foreignRateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            10_000_000e6,
            0
        );

        // Set this for success case
        foreignController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(makeAddr("mintRecipient"))))
        );

        vm.stopPrank();

        deal(Base.USDC, address(foreignAlmProxy), 10_000_000e6 + 1);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(10_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    }

    function test_transferUSDCToCCTP_invalidMintRecipient() external {
        // Configure to pass modifiers
        vm.startPrank(Base.SPARK_EXECUTOR);

        foreignRateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("FC/domain-not-configured");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
    }

}

contract CCTP_Transfer_IntegrationTests is BaseChain_CCTP_TestBase {

    using DomainHelpers       for *;
    using CCTPV2BridgeTesting for Bridge;

    function test_transferUSDCToCCTP_ethToBase() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        assertEq(usdc.balanceOf(address(almProxy)),          1e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY);

        assertEq(usdc.allowance(address(almProxy), Ethereum.CCTP_TOKEN_MESSENGER), 0);

        _expectEthereumCCTPEmit(114_803, 1e6);

        vm.record();

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY - 1e6);

        assertEq(usdc.allowance(address(almProxy), Ethereum.CCTP_TOKEN_MESSENGER), 0);

        baseDomain.selectFork();

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply);

        CCTPV2BridgeTesting.relayMessagesToDestination(ethBridge, true);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   1e6);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply + 1e6);
    }

    function test_transferUSDCToCCTP_ethToBase_bigTransfer() external {
        deal(Ethereum.USDC, address(almProxy), 29_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),          29_000_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY);

        assertEq(usdc.allowance(address(almProxy), Ethereum.CCTP_TOKEN_MESSENGER), 0);

        // Will split into 3 separate transactions at max 1m each
        _expectEthereumCCTPEmit(114_803, 10_000_000e6);
        _expectEthereumCCTPEmit(114_804, 10_000_000e6);
        _expectEthereumCCTPEmit(114_805, 9_000_000e6);

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(29_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY - 29_000_000e6);

        assertEq(usdc.allowance(address(almProxy), Ethereum.CCTP_TOKEN_MESSENGER), 0);

        baseDomain.selectFork();

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply);

        CCTPV2BridgeTesting.relayMessagesToDestination(ethBridge, true);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   29_000_000e6);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply + 29_000_000e6);
    }

    function test_transferUSDCToCCTP_ethToBase_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDC_TO_CCTP();
        deal(Ethereum.USDC, address(almProxy), 51_000_000e6);

        vm.startPrank(relayer);

        assertEq(usdc.balanceOf(address(almProxy)),   51_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 50_000_000e6);

        mainnetController.transferUSDCToCCTP(2_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(usdc.balanceOf(address(almProxy)),   49_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 48_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferUSDCToCCTP(48_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        mainnetController.transferUSDCToCCTP(48_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(usdc.balanceOf(address(almProxy)),   1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(4 hours);

        assertEq(usdc.balanceOf(address(almProxy)),   1_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 999_999.9936e6);

        mainnetController.transferUSDCToCCTP(999_999.9936e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(usdc.balanceOf(address(almProxy)),   0.006400e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.stopPrank();
    }

    function test_transferUSDCToCCTP_baseToETH() external {
        baseDomain.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 1e6);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   1e6);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(usdcBase.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER_V1), 0);

        _expectBaseCCTPEmit(814_408, 1e6);

        vm.record();

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply - 1e6);

        assertEq(usdcBase.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER_V1), 0);

        ethDomain.selectFork();

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY);

        CCTPBridgeTesting.relayMessagesToDestination(baseBridge, true);

        assertEq(usdc.balanceOf(address(almProxy)),          1e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY + 1e6);
    }

    function test_transferUSDCToCCTP_baseToETH_bigTransfer() external {
        baseDomain.selectFork();

        deal(Base.USDC, address(foreignAlmProxy), 2_600_000e6);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   2_600_000e6);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply);

        assertEq(usdcBase.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER_V1), 0);

        // Will split into three separate transactions at max 1m each
        _expectBaseCCTPEmit(814_408, 1_000_000e6);
        _expectBaseCCTPEmit(814_409, 1_000_000e6);
        _expectBaseCCTPEmit(814_410, 600_000e6);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(2_600_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)),   0);
        assertEq(usdcBase.balanceOf(address(foreignController)), 0);
        assertEq(usdcBase.totalSupply(),                         baseUSDCTotalSupply - 2_600_000e6);

        assertEq(usdcBase.allowance(address(foreignAlmProxy), BASE_CCTP_TOKEN_MESSENGER_V1), 0);

        ethDomain.selectFork();

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY);

        CCTPBridgeTesting.relayMessagesToDestination(baseBridge, true);

        assertEq(usdc.balanceOf(address(almProxy)),          2_600_000e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.totalSupply(),                         USDC_SUPPLY + 2_600_000e6);
    }

    function test_transferUSDCToCCTP_baseToETH_rateLimited() external {
        baseDomain.selectFork();

        bytes32 key = foreignController.LIMIT_USDC_TO_CCTP();
        deal(Base.USDC, address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)), 9_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   5_000_000e6);

        foreignController.transferUSDCToCCTP(2_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)), 7_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferUSDCToCCTP(3_000_001e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        foreignController.transferUSDCToCCTP(3_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   0);

        skip(4 hours);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   999_999.9936e6);

        foreignController.transferUSDCToCCTP(999_999.9936e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(usdcBase.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   0);

        vm.stopPrank();
    }

    function _expectEthereumCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(Ethereum.CCTP_TOKEN_MESSENGER);
        emit ICCTPv2Like.DepositForBurn(
            Ethereum.USDC,
            amount,
            address(almProxy),
            mainnetController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(0x00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d),  // TokenMessenger v2
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),  // DestinationCaller
            0,                                                                            // MaxFee
            2_000,                                                                        // MinFinalityThreshold
            ""
        );

        vm.expectEmit(address(mainnetController));
        emit CCTPLib.CCTPTransferInitiated(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mainnetController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            amount
        );
    }

    function _expectBaseCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(BASE_CCTP_TOKEN_MESSENGER_V1);
        emit ICCTPv1Like.DepositForBurn(
            nonce,
            Base.USDC,
            amount,
            address(foreignAlmProxy),
            foreignController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(0x000000000000000000000000bd3fa81b58ba92a82136038b25adec7066af3155),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)
        );

        vm.expectEmit(address(foreignController));
        emit ForeignController.CCTPTransferInitiated(
            nonce,
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            foreignController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            amount
        );
    }

}
