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

import { CCTPForwarder }         from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { Domain, DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { ILayerZeroFacet } from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { LayerZeroFacet }  from "../../src/facets/layer-zero/LayerZeroFacet.sol";

import { makeAddressUint32Key } from "../../src/libraries/RateLimitHelpers.sol";

import { IController } from "../../src/interfaces/IController.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";
import { RateLimits }     from "../../src/RateLimits.sol";

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

    function quoteSend(SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (MessagingFee memory msgFee);

}

interface IPSM3Like {

    function setPocket(address pocket) external;

}

abstract contract LayerZero_TestBase is ForkTestBase {

    address internal constant USDT_OFT = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;

    uint32 internal constant DESTINATION_ENDPOINT_ID = 30110;  // Arbitrum EID

    IERC20Like internal constant USDT = IERC20Like(Ethereum.USDT);

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract MainnetController_LayerZero_TransferToken_Tests is LayerZero_TestBase {

    using OptionsBuilder for bytes;

    function test_transferTokenLayerZero_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.transferTokenLayerZero(USDT_OFT, 1e6, 30110);
    }

    function test_transferTokenLayerZero_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.transferTokenLayerZero(USDT_OFT, 1e6, 30110);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressUint32Key(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            0,
            0
        );

        mainnetController.setLayerZeroRecipient(
            DESTINATION_ENDPOINT_ID,
            bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))))
        );

        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        rateLimits.setRateLimitData(
            makeAddressUint32Key(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            10_000_000e6,
            0
        );

        mainnetController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            DESTINATION_ENDPOINT_ID
        );

        vm.prank(relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_recipientNotSet() external {
        // Set up rate limit, but forget to set recipient
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(
            makeAddressUint32Key(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

        deal(relayer, fee.nativeFee);

        vm.expectRevert("LayerZeroFacet/recipient-not-set");
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_PROXY);

        bytes32 key = makeAddressUint32Key(
            mainnetController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            DESTINATION_ENDPOINT_ID
        );

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        uint256 oftBalanceBefore = USDT.balanceOf(USDT_OFT);

        assertEq(relayer.balance,                     1 ether);
        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

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
        emit ILayerZeroFacet.LayerZeroTransfer({
            oftAddress            : USDT_OFT,
            destinationEndpointId : DESTINATION_ENDPOINT_ID,
            amount                : 10_000_000e6,
            nativeFeePaid         : fee.nativeFee
        });

        vm.prank(relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(relayer.balance,                     1 ether - fee.nativeFee);
        assertEq(USDT.balanceOf(USDT_OFT),            oftBalanceBefore + 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   0);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);
    }

    function test_transferTokenLayerZero_refundExcessNativeFee() external {
        vm.startPrank(SPARK_PROXY);

        bytes32 key = makeAddressUint32Key(
            mainnetController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            DESTINATION_ENDPOINT_ID
        );

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(Ethereum.USDT, address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        uint256 oftBalanceBefore = USDT.balanceOf(USDT_OFT);

        assertEq(relayer.balance,                     1 ether);
        assertEq(address(mainnetController).balance,  0);
        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

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
        emit ILayerZeroFacet.LayerZeroTransfer({
            oftAddress            : USDT_OFT,
            destinationEndpointId : DESTINATION_ENDPOINT_ID,
            amount                : 10_000_000e6,
            nativeFeePaid         : fee.nativeFee
        });

        // Sending more native token than required to cover the fee.
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee + 0.1 ether}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice();

        assertEq(relayer.balance,                     1 ether - fee.nativeFee); // Relayer should be refunded the excess.
        assertEq(address(mainnetController).balance,  0); // Controller should not keep any of the excess native token.
        assertEq(USDT.balanceOf(USDT_OFT),            oftBalanceBefore + 10_000_000e6);
        assertEq(USDT.balanceOf(address(almProxy)),   0);
        assertEq(rateLimits.getCurrentRateLimit(key), 0);
    }

}

abstract contract ArbitrumChain_LayerZero_TestBase is ForkTestBase {

    using DomainHelpers for *;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address internal pocket = makeAddr("pocket");

    /**********************************************************************************************/
    /*** Arbitrum addresses                                                                     ***/
    /**********************************************************************************************/

    address internal constant CCTP_MESSENGER_ARB = Arbitrum.CCTP_TOKEN_MESSENGER;
    address internal constant SPARK_EXECUTOR     = Arbitrum.SPARK_EXECUTOR;
    address internal constant SSR_ORACLE         = Arbitrum.SSR_AUTH_ORACLE;
    address internal constant USDT_OFT           = 0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92;
    address internal constant USDT0              = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy               internal foreignAlmProxy;
    IForeignControllerFull internal foreignController;
    PAUFactory             internal foreignFactory;
    RateLimits             internal foreignRateLimits;

    /**********************************************************************************************/
    /*** Casted addresses for testing                                                           ***/
    /**********************************************************************************************/

    uint32 internal constant DESTINATION_ENDPOINT_ID = 30101;  // Ethereum EID

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

        foreignAlmProxy   = new ALMProxy(SPARK_EXECUTOR);
        foreignRateLimits = new RateLimits(SPARK_EXECUTOR);

        AccessControls foreignAccessControls = new AccessControls(SPARK_EXECUTOR);

        foreignFactory = new PAUFactory(SPARK_EXECUTOR, SPARK_EXECUTOR);

        foreignController = IForeignControllerFull(payable(address(new Controller({
            proxy_          : address(foreignAlmProxy),
            rateLimits_     : address(foreignRateLimits),
            accessControls_ : address(foreignAccessControls),
            factory_        : address(foreignFactory)
        }))));

        vm.startPrank(SPARK_EXECUTOR);

        foreignAccessControls.grantRole(foreignAccessControls.RELAYER_ROLE(), relayer);
        foreignAccessControls.grantRole(foreignAccessControls.FREEZER_ROLE(), freezer);

        foreignAlmProxy.grantRole(foreignAlmProxy.CONTROLLER(), address(foreignController));

        foreignRateLimits.grantRole(foreignRateLimits.CONTROLLER(), address(foreignController));

        // Facet wiring
        _wireLayerZeroFacetForeignController();

        vm.stopPrank();
    }

    function _wireLayerZeroFacetForeignController() internal {
        address layerZeroFacet = address(new LayerZeroFacet());

        vm.label(layerZeroFacet, "LayerZeroFacet");

        foreignFactory.setValidFacet(layerZeroFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](4);

        wires[0] = IController.Wire(
            IForeignControllerFull.setLayerZeroRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.transferTokenLayerZero.selector,
            ILayerZeroFacet.transfer.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.LIMIT_LAYERZERO_TRANSFER.selector,
            ILayerZeroFacet.LIMIT_TRANSFER.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.layerZeroRecipients.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        foreignController.addWires(layerZeroFacet, wires);
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

    function setUp() public override virtual {
        super.setUp();
        destination.selectFork();
    }

    function test_transferTokenLayerZero_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.transferTokenLayerZero(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        foreignController.transferTokenLayerZero(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(
            makeAddressUint32Key(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            0,
            0
        );

        foreignController.setLayerZeroRecipient(
            DESTINATION_ENDPOINT_ID,
            bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))))
        );

        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferTokenLayerZero(USDT_OFT, 1e6, DESTINATION_ENDPOINT_ID);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_EXECUTOR);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        foreignRateLimits.setRateLimitData(
            makeAddressUint32Key(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            10_000_000e6,
            0
        );

        foreignController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            DESTINATION_ENDPOINT_ID
        );

        vm.prank(relayer);
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero_recipientNotSet() external {
        // Set up rate limit, but forget to set recipient
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(
            makeAddressUint32Key(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                DESTINATION_ENDPOINT_ID
            ),
            10_000_000e6,
            0
        );

        vm.stopPrank();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

        deal(relayer, fee.nativeFee);

        vm.expectRevert("LayerZeroFacet/recipient-not-set");
        vm.prank(relayer);
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );
    }

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_EXECUTOR);

        bytes32 key = makeAddressUint32Key(
            foreignController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            DESTINATION_ENDPOINT_ID
        );

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        assertEq(relayer.balance,                                       1 ether);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            10_000_000e6);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

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
        emit ILayerZeroFacet.LayerZeroTransfer({
            oftAddress            : USDT_OFT,
            destinationEndpointId : DESTINATION_ENDPOINT_ID,
            amount                : 10_000_000e6,
            nativeFeePaid         : fee.nativeFee
        });

        vm.prank(relayer);
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(relayer.balance,                                       1 ether - fee.nativeFee);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            0);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 0);
    }

    function test_transferTokenLayerZero_refundExcessNativeFee() external {
        vm.startPrank(SPARK_EXECUTOR);

        bytes32 key = makeAddressUint32Key(
            foreignController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            DESTINATION_ENDPOINT_ID
        );

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.setLayerZeroRecipient(DESTINATION_ENDPOINT_ID, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        assertEq(relayer.balance,                                       1 ether);
        assertEq(address(foreignController).balance,                    0);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            10_000_000e6);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        ILayerZeroLike.SendParam memory sendParams = ILayerZeroLike.SendParam({
            dstEid       : DESTINATION_ENDPOINT_ID,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        ILayerZeroLike.MessagingFee memory fee = ILayerZeroLike(USDT_OFT).quoteSend(sendParams, false);

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
        emit ILayerZeroFacet.LayerZeroTransfer({
            oftAddress            : USDT_OFT,
            destinationEndpointId : DESTINATION_ENDPOINT_ID,
            amount                : 10_000_000e6,
            nativeFeePaid         : fee.nativeFee
        });

        // Sending more native token than required to cover the fee.
        vm.prank(relayer);
        foreignController.transferTokenLayerZero{value: fee.nativeFee + 0.1 ether}(
            USDT_OFT,
            10_000_000e6,
            DESTINATION_ENDPOINT_ID
        );

        _assertReentrancyGuardWrittenToTwice(address(foreignController));

        assertEq(relayer.balance,                                       1 ether - fee.nativeFee); // Relayer should be refunded the excess.
        assertEq(address(foreignController).balance,                    0); // Controller should not keep any of the excess native token.
        assertEq(foreignRateLimits.getCurrentRateLimit(key),            0);
        assertEq(IERC20Like(USDT0).balanceOf(address(foreignAlmProxy)), 0);
    }

}
