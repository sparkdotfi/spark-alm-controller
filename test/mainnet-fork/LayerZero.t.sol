// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    OptionsBuilder
} from "../../lib/layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { ERC20Mock }       from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { Arbitrum } from "../../lib/spark-address-registry/src/Arbitrum.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";

import { Domain, DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { ILayerZeroFacet } from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { LayerZeroFacet }  from "../../src/facets/layer-zero/LayerZeroFacet.sol";

import { IAccessControls }         from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }               from "../../src/interfaces/IALMProxy.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";
import { IRateLimits }             from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

import { IForeignControllerFull } from "../interfaces/IForeignControllerFull.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

}

interface ILayerZeroLike {

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct SendParam {
        uint32  dstEid;
        bytes32 to;
        uint256 amountLD;
        uint256 minAmountLD;
        bytes   extraOptions;
        bytes   composeMsg;
        bytes   oftCmd;
    }

    event OFTSent(
        bytes32 indexed guid,
        uint32          dstEid,
        address indexed fromAddress,
        uint256         amountSentLD,
        uint256         amountReceivedLD
    );

    function decimalConversionRate() external view returns (uint256);

    function quoteSend(SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (MessagingFee memory msgFee);

    function token() external view returns (address);

}

interface IPSM3Like {

    function setPocket(address pocket) external;

}

contract MockOFT {

    uint256 public counter;

    function quoteSend(ILayerZeroFacet.SendParam calldata sendParam, bool useQuote)
        external
        returns (ILayerZeroFacet.MessagingFee memory fee)
    {
        counter++;

        return ILayerZeroFacet.MessagingFee({
            nativeFee: 11,
            lzTokenFee: 22
        });
    }

    function decimalConversionRate() external pure returns (uint256) {
        return 1e6;
    }

}

abstract contract LayerZero_TestBase is ForkTestBase {

    address internal constant USDT_OFT = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;

    uint32 internal constant DESTINATION_ENDPOINT_ID = 30110;  // Arbitrum EID

    bytes32 internal constant PEER = 0x00000000000000000000000014e4a1b13bf7f943c8ff7c51fb60fa964a298d92; // USDT OFT on Arbitrum

    IERC20Like internal constant USDT = IERC20Like(Ethereum.USDT);

    bytes32 internal target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

    bytes32 internal key;

    function setUp() public override {
        super.setUp();

        key = mainnetController.layerZero_getTransferRateLimitKey(
            USDT_OFT,
            PEER,
            DESTINATION_ENDPOINT_ID,
            Ethereum.USDT
        );
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract MainnetController_LayerZero_TransferToken_Tests is LayerZero_TestBase {

    using OptionsBuilder for bytes;

    function test_transferTokenLayerZero_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.layerZero_transfer(USDT_OFT, 1e6, 30110);
    }

    function test_transferTokenLayerZero_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        mainnetController.layerZero_transfer(USDT_OFT, 1e6, 30110);
    }

    function test_transferTokenLayerZero_recipientNotSet() external {
        vm.expectRevert("LayerZeroFacet/recipient-not-set");
        vm.prank(allocator);
        mainnetController.layerZero_transfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_zeroMinAmount() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        deal(allocator, 0.1 ether);

        uint256 decimalConversionRate = ILayerZeroLike(USDT_OFT).decimalConversionRate();

        uint256 amount = decimalConversionRate - 1;

        vm.expectRevert("LayerZeroFacet/zero-min-amount");
        vm.prank(allocator);
        mainnetController.layerZero_transfer{value: 0.1 ether}(
            USDT_OFT,
            amount,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.prank(SPARK_PROXY);
        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        mainnetController.layerZero_transfer(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for LayerZero

        ( , ILayerZeroFacet.MessagingFee memory fee ) = mainnetController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        mainnetController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            DESTINATION_ENDPOINT_ID
        );

        vm.prank(allocator);
        mainnetController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for LayerZero

        uint256 oftStartingUSDT = USDT.balanceOf(USDT_OFT);

        assertEq(allocator.balance,                   1 ether);
        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   10_000_000e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = mainnetController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.record();

        vm.expectEmit(USDT_OFT);
        emit ILayerZeroLike.OFTSent({
            guid             : bytes32(0xb6ebf135f758657b482818d84091e50f1af1cb378bd6f4e013f45dfa6f860cd6),
            dstEid           : DESTINATION_ENDPOINT_ID,
            fromAddress      : address(almProxy),
            amountSentLD     : 10_000_000e6,
            amountReceivedLD : 10_000_000e6
        });

        vm.expectEmit(address(mainnetController));
        emit ILayerZeroFacet.LayerZeroTransfer(USDT_OFT, DESTINATION_ENDPOINT_ID, 10_000_000e6, fee.nativeFee);

        vm.prank(allocator);
        mainnetController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(allocator.balance,                   1 ether - fee.nativeFee);
        assertEq(USDT.balanceOf(USDT_OFT),            oftStartingUSDT + 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   0);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);
    }

    function test_transferTokenLayerZero_refundExcessNativeFee() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup ETH balances
        deal(allocator,                  1 ether);    // Gas cost for LayerZero
        deal(address(almProxy),          0.4 ether);  // Some starting ETH for the controller.
        deal(address(mainnetController), 0.2 ether);  // Some starting ETH for the controller.

        // Setup USDT balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);

        uint256 oftStartingUSDT = USDT.balanceOf(USDT_OFT);

        assertEq(allocator.balance,                   1 ether);
        assertEq(address(almProxy).balance,           0.4 ether);
        assertEq(address(mainnetController).balance,  0.2 ether);
        assertEq(USDT.balanceOf(address(almProxy)),   10_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = mainnetController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.record();

        vm.expectEmit(USDT_OFT);
        emit ILayerZeroLike.OFTSent({
            guid             : bytes32(0xb6ebf135f758657b482818d84091e50f1af1cb378bd6f4e013f45dfa6f860cd6),
            dstEid           : DESTINATION_ENDPOINT_ID,
            fromAddress      : address(almProxy),
            amountSentLD     : 10_000_000e6,
            amountReceivedLD : 10_000_000e6
        });

        vm.expectEmit(address(mainnetController));
        emit ILayerZeroFacet.LayerZeroTransfer(USDT_OFT, DESTINATION_ENDPOINT_ID, 10_000_000e6, fee.nativeFee);

        uint256 msgValue = fee.nativeFee + 0.1 ether;

        // Sending more native token than required to cover the fee.
        vm.prank(allocator);
        mainnetController.layerZero_transfer{value: msgValue}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(allocator.balance,                   1 ether - msgValue);
        assertEq(address(almProxy).balance,           0.4 ether + 0.1 ether + 0.2 ether); // AlmProxy should be given all excess ETH.
        assertEq(address(mainnetController).balance,  0); // Controller should not keep any excess ETH.
        assertEq(USDT.balanceOf(USDT_OFT),            oftStartingUSDT + 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   0);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);
    }

    function test_quoteTransferLayerZero_quoteSendFailed() external {
        address oft = address(new MockOFT());

        bytes32 recipient = bytes32(type(uint256).max);

        vm.prank(SPARK_PROXY);
        mainnetController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, recipient);

        vm.expectRevert("LayerZeroFacet/quoteSend-failed");
        mainnetController.layerZero_quoteTransfer(oft, 1_000_000e6, DESTINATION_ENDPOINT_ID);
    }

}

abstract contract ArbitrumChain_LayerZero_TestBase is ForkTestBase {

    using DomainHelpers for *;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address internal pocket   = makeAddr("pocket");
    address internal skyAdmin = makeAddr("skyAdmin");

    /**********************************************************************************************/
    /*** Arbitrum addresses                                                                     ***/
    /**********************************************************************************************/

    address internal constant SPARK_EXECUTOR     = Arbitrum.SPARK_EXECUTOR;
    address internal constant SSR_ORACLE         = Arbitrum.SSR_AUTH_ORACLE;
    address internal constant USDT_OFT           = 0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92;
    address internal constant USDT0              = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    Beacon                 internal foreignBeacon;
    IALMProxy              internal foreignAlmProxy;
    IForeignControllerFull internal foreignController;
    IRateLimits            internal foreignRateLimits;

    /**********************************************************************************************/
    /*** Casted addresses for testing                                                           ***/
    /**********************************************************************************************/

    uint32 internal constant DESTINATION_ENDPOINT_ID = 30101;  // Ethereum EID

    bytes32 internal constant PEER = 0x0000000000000000000000006c96de32cea08842dcc4058c14d3aaad7fa41dee; // USDT OFT on Ethereum

    IERC20Like internal constant USDC_ARB = IERC20Like(Arbitrum.USDC);

    address internal usdsArb;
    address internal susdsArb;

    address internal psmArb;

    Domain internal destination;

    function setUp() public override virtual {
        super.setUp();

        /*** Step 1: Set up environment and deploy mocks ***/

        destination = getChain("arbitrum_one").createSelectFork(341038130);  // May 27, 2025

        usdsArb  = address(new ERC20Mock());
        susdsArb = address(new ERC20Mock());

        /*** Step 2: Deploy and configure PSM with a pocket ***/

        deal(usdsArb, address(this), 1e18);  // For seeding PSM during deployment

        psmArb = PSM3Deploy.deploy(
            SPARK_EXECUTOR, Arbitrum.USDC, usdsArb, susdsArb, SSR_ORACLE
        );

        vm.prank(SPARK_EXECUTOR);
        IPSM3Like(psmArb).setPocket(pocket);

        vm.prank(pocket);
        USDC_ARB.approve(psmArb, type(uint256).max);

        /*** Step 3: Deploy and configure ALM system ***/

        foreignBeacon = new Beacon(skyAdmin);

        PAUFactory foreignFactory = new PAUFactory(address(foreignBeacon));

        foreignController = IForeignControllerFull(payable(foreignFactory.deploy(SPARK_EXECUTOR)));
        foreignAlmProxy   = IALMProxy(payable(foreignController.proxy()));
        foreignRateLimits = IRateLimits(foreignController.rateLimits());

        IAccessControls foreignAccessControls = IAccessControls(foreignController.accessControls());

        vm.startPrank(skyAdmin);

        // Facet wiring
        _wireLayerZeroFacetForeignController();

        vm.stopPrank();

        vm.startPrank(SPARK_EXECUTOR);

        foreignAccessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        foreignAccessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role
        //       logic that calls into AccessControls to perform grants and revocations.
        foreignAccessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "LAYER_ZERO_FACET";

        foreignController.updateIntegrations(integrationIds);

        vm.stopPrank();
    }

    function _wireLayerZeroFacetForeignController() internal {
        address layerZeroFacet = address(new LayerZeroFacet());

        vm.label(layerZeroFacet, "LayerZeroFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.layerZero_setRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.layerZero_transfer.selector,
            ILayerZeroFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.layerZero_getRecipient.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.layerZero_getTransferRateLimitKey.selector,
            ILayerZeroFacet.getTransferRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.layerZero_quoteTransfer.selector,
            ILayerZeroFacet.quoteTransfer.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : layerZeroFacet,
            wires : wires
        });

        foreignBeacon.setIntegration("LAYER_ZERO_FACET", config);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

    function _setControllerEntered() internal override {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

}

contract ForeignController_LayerZero_TransferToken_Tests is ArbitrumChain_LayerZero_TestBase {

    using DomainHelpers  for *;
    using OptionsBuilder for bytes;

    bytes32 internal target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

    bytes32 internal key;

    function setUp() public override virtual {
        super.setUp();
        destination.selectFork();

        address token = ILayerZeroLike(USDT_OFT).token();

        key = foreignController.layerZero_getTransferRateLimitKey(
            USDT_OFT,
            PEER,
            DESTINATION_ENDPOINT_ID,
            token
        );
    }

    function test_transferTokenLayerZero_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.layerZero_transfer(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.layerZero_transfer(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_recipientNotSet() external {
        vm.expectRevert("LayerZeroFacet/recipient-not-set");
        vm.prank(allocator);
        foreignController.layerZero_transfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_zeroMinAmount() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        deal(allocator, 0.1 ether);

        uint256 decimalConversionRate = ILayerZeroLike(USDT_OFT).decimalConversionRate();

        uint256 amount = decimalConversionRate - 1;

        vm.expectRevert("LayerZeroFacet/zero-min-amount");
        vm.prank(allocator);
        foreignController.layerZero_transfer{value: 0.1 ether}(
            USDT_OFT,
            amount,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.prank(SPARK_EXECUTOR);
        foreignController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(allocator);
        foreignController.layerZero_transfer(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for LayerZero

        ( , ILayerZeroFacet.MessagingFee memory fee ) = foreignController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(allocator);
        foreignController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            DESTINATION_ENDPOINT_ID
        );

        vm.prank(allocator);
        foreignController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(allocator, 1 ether);  // Gas cost for LayerZero

        assertEq(allocator.balance,                                     1 ether);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            10_000_000e6);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 10_000_000e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = foreignController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.record();

        vm.expectEmit(USDT_OFT);
        emit ILayerZeroLike.OFTSent({
            guid             : bytes32(0xce4454206df6ee6a9cab360f7d76fd11ae258f65a9e8cc88faf1110c0bb36864),
            dstEid           : DESTINATION_ENDPOINT_ID,
            fromAddress      : address(foreignAlmProxy),
            amountSentLD     : 10_000_000e6,
            amountReceivedLD : 10_000_000e6
        });

        vm.expectEmit(address(foreignController));
        emit ILayerZeroFacet.LayerZeroTransfer(USDT_OFT, DESTINATION_ENDPOINT_ID, 10_000_000e6, fee.nativeFee);

        vm.prank(allocator);
        foreignController.layerZero_transfer{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(allocator.balance,                                     1 ether - fee.nativeFee);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            0);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 0);
    }

    function test_transferTokenLayerZero_refundExcessNativeFee() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.layerZero_setRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup ETH balances
        deal(allocator,                  1 ether);    // Gas cost for LayerZero
        deal(address(foreignAlmProxy),   0.4 ether);  // Some starting ETH for the controller.
        deal(address(foreignController), 0.2 ether);  // Some starting ETH for the controller.

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);

        assertEq(allocator.balance,                                     1 ether);
        assertEq(address(foreignAlmProxy).balance,                      0.4 ether);
        assertEq(address(foreignController).balance,                    0.2 ether);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 10_000_000e6);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            10_000_000e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = foreignController.layerZero_quoteTransfer(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        vm.record();

        vm.expectEmit(USDT_OFT);
        emit ILayerZeroLike.OFTSent({
            guid             : bytes32(0xce4454206df6ee6a9cab360f7d76fd11ae258f65a9e8cc88faf1110c0bb36864),
            dstEid           : DESTINATION_ENDPOINT_ID,
            fromAddress      : address(foreignAlmProxy),
            amountSentLD     : 10_000_000e6,
            amountReceivedLD : 10_000_000e6
        });

        vm.expectEmit(address(foreignController));
        emit ILayerZeroFacet.LayerZeroTransfer(USDT_OFT, DESTINATION_ENDPOINT_ID, 10_000_000e6, fee.nativeFee);

        uint256 msgValue = fee.nativeFee + 0.1 ether;

        // Sending more native token than required to cover the fee.
        vm.prank(allocator);
        foreignController.layerZero_transfer{value: msgValue}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(allocator.balance,                                     1 ether - msgValue);
        assertEq(address(foreignAlmProxy).balance,                      0.4 ether + 0.1 ether + 0.2 ether); // AlmProxy should be given all excess ETH.
        assertEq(address(foreignController).balance,                    0); // Controller should not keep any excess ETH.
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 0);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            0);
    }

}
