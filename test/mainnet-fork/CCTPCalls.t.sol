// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { Base }     from "../../lib/spark-address-registry/src/Base.sol";

import { CCTPForwarder }     from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { Bridge }            from "../../lib/xchain-helpers/src/testing/Bridge.sol";
import { DomainHelpers }     from "../../lib/xchain-helpers/src/testing/Domain.sol";
import { CCTPBridgeTesting } from "../../lib/xchain-helpers/src/testing/bridges/CCTPBridgeTesting.sol";

import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";
import { ForeignControllerInit }   from "../../deploy/ForeignControllerInit.sol";

import { CCTPLib } from "../../src/libraries/CCTPLib.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { makeUint32Key }     from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface ICCTPLike {

    event DepositForBurn(
        uint64  indexed nonce,
        address indexed burnToken,
        uint256         amount,
        address indexed depositor,
        bytes32         mintRecipient,
        uint32          destinationDomain,
        bytes32         destinationTokenMessenger,
        bytes32         destinationCaller
    );

}

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

contract MainnetController_CCTP_Transfer_Tests is ForkTestBase {

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
            makeUint32Key(
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
            makeUint32Key(
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
            makeUint32Key(
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
            makeUint32Key(
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

    using DomainHelpers     for *;
    using CCTPBridgeTesting for Bridge;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    IERC20Like internal constant BASE_USDC = IERC20Like(Base.USDC);

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy          internal foreignAlmProxy;
    RateLimits        internal foreignRateLimits;
    ForeignController internal foreignController;

    uint256 internal baseUSDCTotalSupply;

    function setUp() public override virtual {
        super.setUp();

        destination = getChain("base").createSelectFork(20782500);  // October 7, 2024

        /*** Step 3: Deploy and configure ALM system ***/

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin : Base.SPARK_EXECUTOR,
            psm   : address(0),
            usdc  : Base.USDC,
            cctp  : Base.CCTP_TOKEN_MESSENGER
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
            cctp  : Base.CCTP_TOKEN_MESSENGER,
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

        bytes32 domainKeyEthereum = makeUint32Key(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        foreignRateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), usdcMaxAmount, usdcSlope);
        foreignRateLimits.setRateLimitData(domainKeyEthereum,                      usdcMaxAmount, usdcSlope);

        vm.stopPrank();

        baseUSDCTotalSupply = BASE_USDC.totalSupply();

        source.selectFork();

        bridge = CCTPBridgeTesting.createCircleBridge(source, destination);

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(address(foreignAlmProxy))))
        );
    }

    function _setControllerEntered() internal override {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

}

contract ForeignController_CCTP_Transfer_Tests is BaseChain_CCTP_TestBase {

    using DomainHelpers for *;

    function setUp( ) public override {
        super.setUp();
        destination.selectFork();
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
            makeUint32Key(
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
            makeUint32Key(
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
            makeUint32Key(
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
            makeUint32Key(
                foreignController.LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            )
        );

        foreignRateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        vm.stopPrank();

        vm.expectRevert("CCTPLib/domain-not-configured");
        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
    }

}

contract CCTP_Transfer_IntegrationTests is BaseChain_CCTP_TestBase {

    IERC20Like internal constant USDC = IERC20Like(Ethereum.USDC);

    using DomainHelpers     for *;
    using CCTPBridgeTesting for Bridge;

    function test_transferUSDCToCCTP_sourceToDestination() external {
        deal(Ethereum.USDC, address(almProxy), 1e6);

        assertEq(USDC.balanceOf(address(almProxy)),          1e6);
        assertEq(USDC.balanceOf(address(mainnetController)), 0);
        assertEq(USDC.totalSupply(),                         USDC_SUPPLY);

        assertEq(USDC.allowance(address(almProxy), CCTP_MESSENGER), 0);

        _expectEthereumCCTPEmit(114_803, 1e6);

        vm.record();

        vm.prank(relayer);
        mainnetController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

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
        mainnetController.transferUSDCToCCTP(2_900_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

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

        mainnetController.transferUSDCToCCTP(2_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(USDC.balanceOf(address(almProxy)),   7_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferUSDCToCCTP(3_000_001e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        mainnetController.transferUSDCToCCTP(3_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        skip(4 hours);

        assertEq(USDC.balanceOf(address(almProxy)),   4_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 999_999.9936e6);

        mainnetController.transferUSDCToCCTP(999_999.9936e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

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

        _expectBaseCCTPEmit(296_114, 1e6);

        vm.record();

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(1e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

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
        _expectBaseCCTPEmit(296_114, 1_000_000e6);
        _expectBaseCCTPEmit(296_115, 1_000_000e6);
        _expectBaseCCTPEmit(296_116, 600_000e6);

        vm.prank(relayer);
        foreignController.transferUSDCToCCTP(2_600_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

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

        bytes32 key = foreignController.LIMIT_USDC_TO_CCTP();
        deal(Base.USDC, address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 9_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   5_000_000e6);

        foreignController.transferUSDCToCCTP(2_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 7_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   3_000_000e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferUSDCToCCTP(3_000_001e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        foreignController.transferUSDCToCCTP(3_000_000e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   0);

        skip(4 hours);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 4_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   999_999.9936e6);

        foreignController.transferUSDCToCCTP(999_999.9936e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(BASE_USDC.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),   0);

        vm.stopPrank();
    }

    function _expectEthereumCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(CCTP_MESSENGER);
        emit ICCTPLike.DepositForBurn(
            nonce,
            Ethereum.USDC,
            amount,
            address(almProxy),
            mainnetController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(0x0000000000000000000000001682ae6375c4e4a97e4b583bc394c861a46d8962),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000)
        );

        vm.expectEmit(address(mainnetController));
        emit CCTPLib.CCTPTransferInitiated(
            nonce,
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mainnetController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            amount
        );
    }

    function _expectBaseCCTPEmit(uint64 nonce, uint256 amount) internal {
        // NOTE: Focusing on burnToken, amount, depositor, mintRecipient, and destinationDomain
        //       for assertions
        vm.expectEmit(Base.CCTP_TOKEN_MESSENGER);
        emit ICCTPLike.DepositForBurn(
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
        emit CCTPLib.CCTPTransferInitiated(
            nonce,
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            foreignController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            amount
        );
    }

}
