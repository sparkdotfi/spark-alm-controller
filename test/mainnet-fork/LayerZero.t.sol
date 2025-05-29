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

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";
import { RateLimitHelpers }  from "../../src/RateLimitHelpers.sol";

import "src/interfaces/ILayerZero.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

contract MainnetControllerLayerZeroTestBase is ForkTestBase {

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract MainnetControllerTransferLayerZeroFailureTests is MainnetControllerLayerZeroTestBase {

    uint32 destinationEndpointId = 30110; // Arbitrum EID

    address OFT_ADDRESS = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;  // USDT OFT address

    function test_transferTokenLayerZero_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.transferTokenLayerZero(OFT_ADDRESS, 1e6, 30110);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                OFT_ADDRESS,
                destinationEndpointId
            )),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.transferTokenLayerZero(OFT_ADDRESS, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_PROXY);

        rateLimits.setRateLimitData(
            keccak256(abi.encode(
                mainnetController.LIMIT_LAYERZERO_TRANSFER(),
                OFT_ADDRESS,
                destinationEndpointId
            )),
            10_000_000e6,
            0
        );

        mainnetController.setLayerZeroRecipient(
            destinationEndpointId,
            makeAddr("layerZeroRecipient")
        );

        vm.stopPrank();

        // Setup token balances
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(almProxy), 1 ether);   // gas cost for LayerZero

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferTokenLayerZero(OFT_ADDRESS, 10_000_000e6 + 1, destinationEndpointId);

        mainnetController.transferTokenLayerZero(OFT_ADDRESS, 10_000_000e6, destinationEndpointId);
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
            usdc  : address(usdcArb),
            susds : address(susdsArb),
            usds  : address(usdsArb)
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(address(almProxy))))
        });

        vm.startPrank(SPARK_EXECUTOR);

        ForeignControllerInit.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients
        );

        vm.stopPrank();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22468758;  // May 12, 2025
    }

}

contract ForeignControllerTransferLayerZeroFailureTests is ArbitrumChainLayerZeroTestBase {

    using DomainHelpers for *;

    uint32 destinationEndpointId = 30101;  // Ethereum EID

    address ArbitrumExtensionV2 = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address OFT_ADDRESS         = 0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92;  // USDT OFT address

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
        foreignController.transferTokenLayerZero(OFT_ADDRESS, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_zeroMaxAmount() external {
        vm.startPrank(SPARK_EXECUTOR);
        foreignRateLimits.setRateLimitData(
            keccak256(abi.encode(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                OFT_ADDRESS,
                destinationEndpointId
            )),
            0,
            0
        );
        vm.stopPrank();

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        foreignController.transferTokenLayerZero(OFT_ADDRESS, 1e6, destinationEndpointId);
    }

    function test_transferTokenLayerZero_rateLimitedBoundary() external {
        vm.startPrank(SPARK_EXECUTOR);

        foreignRateLimits.setRateLimitData(
            keccak256(abi.encode(
                foreignController.LIMIT_LAYERZERO_TRANSFER(),
                OFT_ADDRESS,
                destinationEndpointId
            )),
            10_000_000e6,
            0
        );

        foreignController.setLayerZeroRecipient(
            destinationEndpointId,
            makeAddr("layerZeroRecipient")
        );

        vm.stopPrank();

        // Setup token balances
        deal(ArbitrumExtensionV2, address(foreignAlmProxy), 10_000_000e6);
        deal(address(foreignAlmProxy), 1 ether);  // gas cost for LayerZero

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferTokenLayerZero(OFT_ADDRESS, 10_000_000e6 + 1, destinationEndpointId);

        foreignController.transferTokenLayerZero(OFT_ADDRESS, 10_000_000e6, destinationEndpointId);
    }

}
