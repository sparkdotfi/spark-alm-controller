// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import "./ForkTestBase.t.sol";

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";

import { PSM3Deploy } from "spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "spark-psm/src/PSM3.sol";

import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";

import { ForeignControllerInit } from "../../deploy/ForeignControllerInit.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { ALMProxy }                from "../../src/ALMProxy.sol";
import { ForeignController }       from "../../src/ForeignController.sol";
import { IRateLimits, RateLimits } from "../../src/RateLimits.sol";
import { RateLimitHelpers }        from "../../src/RateLimitHelpers.sol";

import "src/interfaces/ILayerZero.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

contract MainnetControllerLayerZeroTestBase is ForkTestBase {

    uint32 constant destinationEndpointId = 30110;  // Arbitrum EID

    address constant USDT_OFT = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract MainnetControllerTransferLayerZeroFailureTests is MainnetControllerLayerZeroTestBase {

    using OptionsBuilder for bytes;

    function test_transferTokenLayerZero_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferTokenLayerZero(USDT_OFT, 1e6, 30110);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                destinationEndpointId
            )),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero(USDT_OFT, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                destinationEndpointId
            )),
            10_000_000e6,
            0
        );

        mainnetController.setLayerZeroRecipient(destinationEndpointId, target);

        vm.stopPrank();

        // Setup token balances
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            destinationEndpointId
        );

        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            destinationEndpointId
        );
    }

}

contract MainnetControllerTransferLayerZeroSuccessTests is MainnetControllerLayerZeroTestBase {

    using OptionsBuilder for bytes;

    event OFTSent(
        bytes32 indexed guid, // GUID of the OFT message.
        uint32  dstEid, // Destination Endpoint ID.
        address indexed fromAddress, // Address of the sender on the src chain.
        uint256 amountSentLD, // Amount of tokens sent in local decimals.
        uint256 amountReceivedLD // Amount of tokens received in local decimals.
    );

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_PROXY);

        bytes32 key = keccak256(abi.encode(
            mainnetController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            destinationEndpointId
        ));

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        rateLimits.setRateLimitData(key, 10_000_000e6, 0);

        mainnetController.setLayerZeroRecipient(destinationEndpointId, target);

        vm.stopPrank();

        // Setup token balances
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        uint256 oftBalanceBefore = IERC20(usdt).balanceOf(USDT_OFT);

        vm.startPrank(relayer);

        assertEq(relayer.balance,                           1 ether);
        assertEq(rateLimits.getCurrentRateLimit(key),       10_000_000e6);
        assertEq(IERC20(usdt).balanceOf(address(almProxy)), 10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        vm.expectEmit(USDT_OFT);
        emit OFTSent(
            bytes32(0xb6ebf135f758657b482818d84091e50f1af1cb378bd6f4e013f45dfa6f860cd6),
            destinationEndpointId,
            address(almProxy),
            10_000_000e6,
            10_000_000e6
        );
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            destinationEndpointId
        );

        assertEq(relayer.balance,                           1 ether - fee.nativeFee);
        assertEq(IERC20(usdt).balanceOf(USDT_OFT),          oftBalanceBefore + 10_000_000e6);
        assertEq(IERC20(usdt).balanceOf(address(almProxy)), 0);
        assertEq(rateLimits.getCurrentRateLimit(key),       0);
    }

}

contract ArbitrumChainLayerZeroTestBase is ForkTestBase {

    using DomainHelpers for *;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address pocket = makeAddr("pocket");

    /**********************************************************************************************/
    /*** Arbtirum addresses                                                                     ***/
    /**********************************************************************************************/

    address constant CCTP_MESSENGER_ARB = Arbitrum.CCTP_TOKEN_MESSENGER;
    address constant SPARK_EXECUTOR     = Arbitrum.SPARK_EXECUTOR;
    address constant SSR_ORACLE         = Arbitrum.SSR_AUTH_ORACLE;
    address constant USDC_ARB           = Arbitrum.USDC;
    address constant USDT_OFT           = 0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92;
    address constant USDT0              = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy          foreignAlmProxy;
    RateLimits        foreignRateLimits;
    ForeignController foreignController;

    /**********************************************************************************************/
    /*** Casted addresses for testing                                                           ***/
    /**********************************************************************************************/

    IERC20 usdsArb;
    IERC20 susdsArb;
    IERC20 usdcArb;

    IPSM3 psmArb;

    uint32 constant destinationEndpointId = 30101;  // Ethereum EID

    function setUp() public override virtual {
        super.setUp();

        /*** Step 1: Set up environment and deploy mocks ***/

        destination = getChain("arbitrum_one").createSelectFork(341038130);  // May 27, 2025

        usdsArb  = IERC20(address(new ERC20Mock()));
        susdsArb = IERC20(address(new ERC20Mock()));
        usdcArb  = IERC20(USDC_ARB);

        /*** Step 2: Deploy and configure PSM with a pocket ***/

        deal(address(usdsArb), address(this), 1e18);  // For seeding PSM during deployment

        psmArb = IPSM3(PSM3Deploy.deploy(
            SPARK_EXECUTOR, USDC_ARB, address(usdsArb), address(susdsArb), SSR_ORACLE
        ));

        vm.prank(SPARK_EXECUTOR);
        psmArb.setPocket(pocket);

        vm.prank(pocket);
        usdcArb.approve(address(psmArb), type(uint256).max);

        /*** Step 3: Deploy and configure ALM system ***/

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin : SPARK_EXECUTOR,
            psm   : address(psmArb),
            usdc  : USDC_ARB,
            cctp  : CCTP_MESSENGER_ARB
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
            admin : SPARK_EXECUTOR,
            psm   : address(psmArb),
            cctp  : CCTP_MESSENGER_ARB,
            usdc  : address(usdcArb)
            // susds : address(susdsArb),
            // usds  : address(usdsArb)
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(address(almProxy))))
        });

        ForeignControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new ForeignControllerInit.LayerZeroRecipient[](0);

        ForeignControllerInit.CentrifugeRecipient[] memory centrifugeRecipients = new ForeignControllerInit.CentrifugeRecipient[](0);

        vm.startPrank(SPARK_EXECUTOR);

        ForeignControllerInit.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients,
            layerZeroRecipients,
            centrifugeRecipients
        );

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract ForeignControllerTransferLayerZeroFailureTests is ArbitrumChainLayerZeroTestBase {

    using DomainHelpers  for *;
    using OptionsBuilder for bytes;

    function setUp() public override virtual {
        super.setUp();
        destination.selectFork();
    }

    function test_transferTokenLayerZero_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.transferTokenLayerZero(USDT_OFT, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(
            keccak256(abi.encode(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                destinationEndpointId
            )),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferTokenLayerZero(USDT_OFT, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_EXECUTOR);

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        foreignRateLimits.setRateLimitData(
            keccak256(abi.encode(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                USDT_OFT,
                destinationEndpointId
            )),
            10_000_000e6,
            0
        );

        foreignController.setLayerZeroRecipient(
            destinationEndpointId,
            target
        );

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6 + 1,
            destinationEndpointId
        );

        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            destinationEndpointId
        );
    }

}


contract ForeignControllerTransferLayerZeroSuccessTests is ArbitrumChainLayerZeroTestBase {

    using DomainHelpers  for *;
    using OptionsBuilder for bytes;

    event OFTSent(
        bytes32 indexed guid, // GUID of the OFT message.
        uint32  dstEid, // Destination Endpoint ID.
        address indexed fromAddress, // Address of the sender on the src chain.
        uint256 amountSentLD, // Amount of tokens sent in local decimals.
        uint256 amountReceivedLD // Amount of tokens received in local decimals.
    );

    function setUp() public override virtual {
        super.setUp();
        destination.selectFork();
    }

    function test_transferTokenLayerZero() external {
        vm.startPrank(SPARK_EXECUTOR);

        bytes32 key = keccak256(abi.encode(
            foreignController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            destinationEndpointId
        ));

        bytes32 target = bytes32(uint256(uint160(makeAddr("layerZeroRecipient"))));

        foreignRateLimits.setRateLimitData(key, 10_000_000e6, 0);

        foreignController.setLayerZeroRecipient(destinationEndpointId, target);

        vm.stopPrank();

        // Setup token balances
        deal(USDT0, address(foreignAlmProxy), 10_000_000e6);
        deal(relayer, 1 ether);  // Gas cost for LayerZero

        vm.startPrank(relayer);

        assertEq(relayer.balance,                                   1 ether);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),        10_000_000e6);
        assertEq(IERC20(USDT0).balanceOf(address(foreignAlmProxy)), 10_000_000e6);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        SendParam memory sendParams = SendParam({
            dstEid       : destinationEndpointId,
            to           : target,
            amountLD     : 10_000_000e6,
            minAmountLD  : 10_000_000e6,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });

        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        vm.expectEmit(USDT_OFT);
        emit OFTSent(
            bytes32(0xce4454206df6ee6a9cab360f7d76fd11ae258f65a9e8cc88faf1110c0bb36864),
            destinationEndpointId,
            address(foreignAlmProxy),
            10_000_000e6,
            10_000_000e6
        );
        foreignController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            10_000_000e6,
            destinationEndpointId
        );

        assertEq(relayer.balance,                                   1 ether - fee.nativeFee);
        assertEq(foreignRateLimits.getCurrentRateLimit(key),        0);
        assertEq(IERC20(USDT0).balanceOf(address(foreignAlmProxy)), 0);
    }

}
