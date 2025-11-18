// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {PSM3Deploy} from "spark-psm/deploy/PSM3Deploy.sol";
import {IPSM3} from "spark-psm/src/PSM3.sol";
import {MockRateProvider} from "spark-psm/test/mocks/MockRateProvider.sol";
import {IRateProviderLike} from "spark-psm/src/interfaces/IRateProviderLike.sol";

import {LZBridgeTesting} from "xchain-helpers/testing/bridges/LZBridgeTesting.sol";
import {LZForwarder} from "xchain-helpers/forwarders/LZForwarder.sol";

import {ForeignControllerDeploy} from "../../deploy/ControllerDeploy.sol";
import {ControllerInstance} from "../../deploy/ControllerInstance.sol";

import {ForeignControllerInit} from "../../deploy/ForeignControllerInit.sol";

import {ALMProxy} from "../../src/ALMProxy.sol";
import {ForeignController} from "../../src/ForeignController.sol";
import {RateLimits} from "../../src/RateLimits.sol";
import {RateLimitHelpers} from "../../src/RateLimitHelpers.sol";

import "./ForkTestBase.t.sol";

contract PlasmaChainUSDTToLayerZeroTestBase is ForkTestBase {
    using DomainHelpers for *;
    using LZBridgeTesting for Bridge;

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address pocket = makeAddr("pocket");


    /**********************************************************************************************/
    /*** Plasma addresses                                                                         ***/
    /**********************************************************************************************/

    // Plasma OUpgradeable USDT OFT
    address constant USDT0_OFT_PLASMA_ADDRESS = 0x02ca37966753bDdDf11216B73B16C1dE756A7CF9;
    // Plasma USDT0
    address constant USDT0_PLASMA_ADDRESS     = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy          foreignAlmProxy;
    RateLimits        foreignRateLimits;
    ForeignController foreignController;

    /**********************************************************************************************/
    /*** Casted addresses for testing                                                           ***/
    /**********************************************************************************************/

    // Mainnet OFTs
    IERC20 usdtOft;

    // Plasma Tokens
    IERC20 usdsPlasma;
    IERC20 susdsPlasma;
    IERC20 usdt0Plasma;
    IERC20 usdt0OftPlasma;

    IPSM3 psmPlasma;

    uint256 USDT0_PLASMA_SUPPLY; // Total supply of USDT0 on Plasma
    uint256 USDT0_MAINNET_BALANCE_BEFORE; // How much USDT is in the mainnet OFT contract before the test

    uint32 constant sourceEndpointId      = 30101; // Ethereum EID
    uint32 constant destinationEndpointId = 30383; // Plasma EID

    bytes32 sourceRateLimitKey;
    bytes32 destinationRateLimitKey;

    function setUp() public virtual override {
        super.setUp();

        /**
         * Step 1: Set up environment and deploy mocks **
         */
        setChain(
            "plasma",
            ChainData({
                name: "plasma",
                chainId: 9745,
                rpcUrl: vm.envString("PLASMA_RPC_URL")
            })
        );

        destination = getChain("plasma").createSelectFork(_getDestinationBlock());

        usdsPlasma      = IERC20(address(new ERC20Mock()));
        susdsPlasma     = IERC20(address(new ERC20Mock()));
        usdt0Plasma     = IERC20(USDT0_PLASMA_ADDRESS);
        usdt0OftPlasma  = IERC20(USDT0_OFT_PLASMA_ADDRESS);

        USDT0_PLASMA_SUPPLY = usdt0Plasma.totalSupply();

        /**
         * Step 2: Deploy and configure PSM with a pocket **
         */
        MockRateProvider mockRateProvider = new MockRateProvider();
        mockRateProvider.__setConversionRate(1.25e27);

        IRateProviderLike rateProvider = IRateProviderLike(address(mockRateProvider));

        deal(address(usdsPlasma), address(this), 1e18); // For seeding PSM during deployment

        psmPlasma = IPSM3(
            PSM3Deploy.deploy(
                Ethereum.GROVE_PROXY,
                address(usdt0Plasma),
                address(usdsPlasma),
                address(susdsPlasma),
                address(rateProvider)
            )
        );

        vm.prank(Ethereum.GROVE_PROXY);
        psmPlasma.setPocket(pocket);

        vm.prank(pocket);
        usdt0Plasma.approve(address(psmPlasma), type(uint256).max);

        /**
         * Step 3: Deploy and configure ALM system **
         */
        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin                    : Ethereum.GROVE_PROXY,
            psm                      : address(psmPlasma),
            usdc                     : address(usdt0Plasma),
            cctp                     : address(0xDeadBeef), // unused
            pendleRouter             : address(0xDeadBeef), // unused
            uniswapV3Router          : address(0xDeadBeef), // unused
            uniswapV3PositionManager : address(0xDeadBeef)  // unused
        });

        foreignAlmProxy   = ALMProxy(payable(controllerInst.almProxy));
        foreignRateLimits = RateLimits(controllerInst.rateLimits);
        foreignController = ForeignController(controllerInst.controller);

        deal(address(foreignController), 100 ether); // LZ gas costs

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;

        ForeignControllerInit.ConfigAddressParams memory configAddresses =
            ForeignControllerInit.ConfigAddressParams({freezer: freezer, relayers: relayers, oldController: address(0)});

        ForeignControllerInit.CheckAddressParams memory checkAddresses = ForeignControllerInit.CheckAddressParams({
            admin                    : Ethereum.GROVE_PROXY,
            psm                      : address(psmPlasma),
            cctp                     : address(0xDeadBeef), // unused
            usdc                     : address(usdt0Plasma),
            pendleRouter             : address(0xDeadBeef), // unused
            uniswapV3Router          : address(0xDeadBeef), // unused
            uniswapV3PositionManager : address(0xDeadBeef)  // unused
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain:        CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient: bytes32(uint256(uint160(address(almProxy))))
        });

        ForeignControllerInit.LayerZeroRecipient[] memory layerZeroRecipients =
            new ForeignControllerInit.LayerZeroRecipient[](1);
        layerZeroRecipients[0] = ForeignControllerInit.LayerZeroRecipient({
            destinationEndpointId: LZForwarder.ENDPOINT_ID_ETHEREUM,
            recipient:             bytes32(uint256(uint160(address(almProxy))))
        });

        ForeignControllerInit.CentrifugeRecipient[] memory centrifugeRecipients =
            new ForeignControllerInit.CentrifugeRecipient[](0);

        vm.startPrank(Ethereum.GROVE_PROXY);

        ForeignControllerInit.initAlmSystem(
            controllerInst, configAddresses, checkAddresses, mintRecipients, layerZeroRecipients, centrifugeRecipients
        );

        destinationRateLimitKey =
            keccak256(abi.encode(foreignController.LIMIT_LAYERZERO_TRANSFER(), usdt0OftPlasma, sourceEndpointId));

        uint256 usdt0PlasmaMaxAmount = 5_000_000e6;
        uint256 usdt0PlasmaSlope     = uint256(1_000_000e6) / 4 hours;

        foreignRateLimits.setRateLimitData(destinationRateLimitKey, usdt0PlasmaMaxAmount, usdt0PlasmaSlope);
        vm.stopPrank();

        /**
         * Step 4: Set up mainnet **
         */
        source.selectFork();

        usdtOft = IERC20(0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee);

        // Gas cost for LZ
        deal(address(mainnetController), 1 ether);

        bridge = LZBridgeTesting.createLZBridge(source, destination);

        vm.startPrank(Ethereum.GROVE_PROXY);
        sourceRateLimitKey =
            keccak256(abi.encode(mainnetController.LIMIT_LAYERZERO_TRANSFER(), usdtOft, destinationEndpointId));
        uint256 usdtMaxAmount = 5_000_000e6;
        uint256 usdtSlope     = uint256(1_000_000e6) / 4 hours;

        rateLimits.setRateLimitData(sourceRateLimitKey, usdtMaxAmount, usdtSlope);

        // Add foreign ALM Proxy as recipient
        mainnetController.setLayerZeroRecipient(
            destinationEndpointId, bytes32(uint256(uint160(address(foreignAlmProxy))))
        );

        USDT0_MAINNET_BALANCE_BEFORE = usdt.balanceOf(address(usdtOft));

        vm.stopPrank();

        /**
         * Step 5: Label addresses **
         */
        _labelAddresses();
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23593452; // Oct-16-2025
    }

    function _getDestinationBlock() internal pure returns (uint256) {
        return 3724081; // Oct-16-2025
    }

    function _labelAddresses() internal {
        vm.label(address(usdsPlasma),               "usdsPlasma");
        vm.label(address(susdsPlasma),             "susdsPlasma");
        vm.label(address(usdt0Plasma),             "usdt0Plasma");
        vm.label(address(usdt0OftPlasma),       "usdt0OftPlasma");
        vm.label(address(usdtOft),                     "usdtOft");
        vm.label(address(usdt),                           "usdt");
        vm.label(address(mainnetController), "mainnetController");
        vm.label(address(foreignAlmProxy),     "foreignAlmProxy");
        vm.label(address(foreignRateLimits), "foreignRateLimits");
        vm.label(address(foreignController), "foreignController");
        vm.label(address(rateLimits),               "rateLimits");
        vm.label(address(almProxy),                   "almProxy");
    }
}

contract USDTToLayerZeroIntegrationTests is PlasmaChainUSDTToLayerZeroTestBase {
    using DomainHelpers for *;
    using LZBridgeTesting for Bridge;

    event OFTSent(
        bytes32 indexed guid, uint32 dstEid, address indexed fromAddress, uint256 amountSentLD, uint256 amountReceivedLD
    );

    function test_transferUSDTToLZ_sourceToDestination() external {
        deal(address(usdt), address(almProxy), 1e6);

        assertEq(usdt.balanceOf(address(almProxy)), 1e6, "ALM Proxy balance should be 1e6 before transfer");
        assertEq(
            usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 before transfer"
        );
        assertEq(
            usdt.balanceOf(address(usdtOft)), USDT0_MAINNET_BALANCE_BEFORE, "OFT balance should be 0 before transfer"
        );

        _expectEthereumOftEmit(1e6);

        vm.prank(relayer);
        mainnetController.transferTokenLayerZero(address(usdtOft), 1e6, destinationEndpointId);

        assertEq(usdt.balanceOf(address(almProxy)), 0, "ALM Proxy balance should be 0 after transfer");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 after transfer");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE + 1e6,
            "OFT balance should be increased by 1e6 after transfer"
        );

        destination.selectFork();

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            0,
            "Foreign ALM Proxy balance should be 0 before message relay"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 before message relay"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY,
            "Total supply should be USDT0_PLASMA_SUPPLY before message relay"
        );

        bridge.relayMessagesToDestination(true, address(usdtOft), address(usdt0OftPlasma));

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            1e6,
            "Foreign ALM Proxy balance should be 1e6 after message relay"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 after message relay"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY + 1e6,
            "Total supply should be increased by 1e6 after message relay"
        );
    }

    function test_transferUSDTToLZ_sourceToDestination_bigTransfer() external {
        deal(address(usdt), address(almProxy), 2_900_000e6);

        assertEq(
            usdt.balanceOf(address(almProxy)), 2_900_000e6, "ALM Proxy balance should be 2_900_000e6 before transfer"
        );
        assertEq(
            usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 before transfer"
        );
        assertEq(
            usdt.balanceOf(address(usdtOft)), USDT0_MAINNET_BALANCE_BEFORE, "OFT balance should be 0 before transfer"
        );

        // Will split into 3 separate transactions at max 1m each
        _expectEthereumOftEmit(2_900_000e6);

        vm.prank(relayer);
        mainnetController.transferTokenLayerZero(address(usdtOft), 2_900_000e6, destinationEndpointId);

        assertEq(usdt.balanceOf(address(almProxy)), 0, "ALM Proxy balance should be 0 after transfer");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 after transfer");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE + 2_900_000e6,
            "OFT balance should be increased by 2_900_000e6 after transfer"
        );

        destination.selectFork();

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            0,
            "Foreign ALM Proxy balance should be 0 before message relay"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 before message relay"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY,
            "Total supply should be USDT0_PLASMA_SUPPLY before message relay"
        );

        bridge.relayMessagesToDestination(true, address(usdtOft), address(usdt0OftPlasma));

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            2_900_000e6,
            "Foreign ALM Proxy balance should be 2_900_000e6 after message relay"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 after message relay"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY + 2_900_000e6,
            "Total supply should be increased by 2_900_000e6 after message relay"
        );
    }

    function test_transferUSDTToLZ_sourceToDestination_rateLimited() external {
        bytes32 key = sourceRateLimitKey;
        deal(address(usdt), address(almProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(
            usdt.balanceOf(address(almProxy)), 9_000_000e6, "ALM Proxy balance should be 9_000_000e6 before transfer"
        );
        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6, "Rate limit should be 5_000_000e6 before transfer");

        mainnetController.transferTokenLayerZero(address(usdtOft), 2_000_000e6, destinationEndpointId);

        assertEq(
            usdt.balanceOf(address(almProxy)), 7_000_000e6, "ALM Proxy balance should be 7_000_000e6 after transfer"
        );
        assertEq(rateLimits.getCurrentRateLimit(key), 3_000_000e6, "Rate limit should be 3_000_000e6 after transfer");

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.transferTokenLayerZero(address(usdtOft), 3_000_001e6, destinationEndpointId);

        mainnetController.transferTokenLayerZero(address(usdtOft), 3_000_000e6, destinationEndpointId);

        assertEq(
            usdt.balanceOf(address(almProxy)), 4_000_000e6, "ALM Proxy balance should be 4_000_000e6 after transfer"
        );
        assertEq(rateLimits.getCurrentRateLimit(key), 0, "Rate limit should be 0 after transfer");

        skip(4 hours);

        assertEq(
            usdt.balanceOf(address(almProxy)), 4_000_000e6, "ALM Proxy balance should be 4_000_000e6 after skipping"
        );
        assertEq(
            rateLimits.getCurrentRateLimit(key), 999_999.9936e6, "Rate limit should be 999_999.9936e6 after skipping"
        );

        mainnetController.transferTokenLayerZero(address(usdtOft), 999_999.9936e6, destinationEndpointId);

        assertEq(
            usdt.balanceOf(address(almProxy)),
            3_000_000.0064e6,
            "ALM Proxy balance should be 3_000_000.0064e6 after transfer"
        );
        assertEq(rateLimits.getCurrentRateLimit(key), 0, "Rate limit should be 0 after transfer");

        vm.stopPrank();
    }

    function test_transferUSDTToLZ_destinationToSource() external {
        destination.selectFork();

        deal(address(usdt0Plasma), address(foreignAlmProxy), 1e6);

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            1e6,
            "Foreign ALM Proxy balance should be 1e6 before transfer"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 before transfer"
        );
        assertEq(
            usdt0Plasma.totalSupply(), USDT0_PLASMA_SUPPLY, "Total supply should be USDT0_PLASMA_SUPPLY before transfer"
        );

        _expectPlasmaOftEmit(1e6);

        vm.prank(relayer);
        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 1e6, sourceEndpointId);

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)), 0, "Foreign ALM Proxy balance should be 0 after transfer"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 after transfer"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY - 1e6,
            "Total supply should be USDT0_PLASMA_SUPPLY - 1e6 after transfer"
        );

        source.selectFork();

        assertEq(usdt.balanceOf(address(almProxy)), 0, "ALM Proxy balance should be 0 before relay");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 before relay");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE,
            "OFT balance should be the same before relay"
        );

        bridge.relayMessagesToSource(true, address(usdt0OftPlasma), address(usdtOft));

        assertEq(usdt.balanceOf(address(almProxy)), 1e6, "ALM Proxy balance should be 1e6 after relay");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 after relay");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE - 1e6,
            "OFT balance should be decreased by 1e6 after relay"
        );
    }

    function test_transferUSDTToLZ_destinationToSource_bigTransfer() external {
        destination.selectFork();

        deal(address(usdt0Plasma), address(foreignAlmProxy), 2_600_000e6);

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)),
            2_600_000e6,
            "Foreign ALM Proxy balance should be 2_600_000e6 before transfer"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 before transfer"
        );
        assertEq(
            usdt0Plasma.totalSupply(), USDT0_PLASMA_SUPPLY, "Total supply should be USDT0_PLASMA_SUPPLY before transfer"
        );

        // Will split into three separate transactions at max 1m each
        _expectPlasmaOftEmit(2_600_000e6);

        vm.prank(relayer);
        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 2_600_000e6, sourceEndpointId);

        assertEq(
            usdt0Plasma.balanceOf(address(foreignAlmProxy)), 0, "Foreign ALM Proxy balance should be 0 after transfer"
        );
        assertEq(
            usdt0Plasma.balanceOf(address(foreignController)),
            0,
            "Foreign Controller balance should be 0 after transfer"
        );
        assertEq(
            usdt0Plasma.totalSupply(),
            USDT0_PLASMA_SUPPLY - 2_600_000e6,
            "Total supply should be USDT0_PLASMA_SUPPLY - 2_600_000e6 after transfer"
        );

        source.selectFork();

        assertEq(usdt.balanceOf(address(almProxy)), 0, "ALM Proxy balance should be 0 before relay");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 before relay");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE,
            "OFT balance should be the same before relay"
        );

        bridge.relayMessagesToSource(true, address(usdt0OftPlasma), address(usdtOft));

        assertEq(usdt.balanceOf(address(almProxy)), 2_600_000e6, "ALM Proxy balance should be 2_600_000e6 after relay");
        assertEq(usdt.balanceOf(address(mainnetController)), 0, "Mainnet Controller balance should be 0 after relay");
        assertEq(
            usdt.balanceOf(address(usdtOft)),
            USDT0_MAINNET_BALANCE_BEFORE - 2_600_000e6,
            "OFT balance should be decreased by 2_600_000e6 after relay"
        );
    }

    function test_transferUSDTToLZ_destinationToSource_rateLimited() external {
        destination.selectFork();

        bytes32 key = destinationRateLimitKey;
        deal(address(usdt0Plasma), address(foreignAlmProxy), 9_000_000e6);

        vm.startPrank(relayer);

        assertEq(usdt0Plasma.balanceOf(address(foreignAlmProxy)), 9_000_000e6, "Foreign ALM Proxy balance should be 9_000_000e6 before transfer");
        assertEq(foreignRateLimits.getCurrentRateLimit(key), 5_000_000e6, "Rate limit should be 5_000_000e6 before transfer");

        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 2_000_000e6, sourceEndpointId);

        assertEq(usdt0Plasma.balanceOf(address(foreignAlmProxy)), 7_000_000e6, "Foreign ALM Proxy balance should be 7_000_000e6 after transfer");
        assertEq(foreignRateLimits.getCurrentRateLimit(key), 3_000_000e6, "Rate limit should be 3_000_000e6 after transfer");

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 3_000_001e6, sourceEndpointId);

        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 3_000_000e6, sourceEndpointId);

        assertEq(usdt0Plasma.balanceOf(address(foreignAlmProxy)), 4_000_000e6, "Foreign ALM Proxy balance should be 4_000_000e6 after transfer");
        assertEq(foreignRateLimits.getCurrentRateLimit(key), 0, "Rate limit should be 0 after transfer");

        skip(4 hours);

        assertEq(usdt0Plasma.balanceOf(address(foreignAlmProxy)), 4_000_000e6, "Foreign ALM Proxy balance should be 4_000_000e6 after skipping");
        assertEq(foreignRateLimits.getCurrentRateLimit(key), 999_999.9936e6, "Rate limit should be 999_999.9936e6 after skipping");

        foreignController.transferTokenLayerZero(address(usdt0OftPlasma), 999_999.9936e6, sourceEndpointId);

        assertEq(usdt0Plasma.balanceOf(address(foreignAlmProxy)), 3_000_000.0064e6, "Foreign ALM Proxy balance should be 3_000_000.0064e6 after transfer");
        assertEq(foreignRateLimits.getCurrentRateLimit(key), 0, "Rate limit should be 0 after transfer");

        vm.stopPrank();
    }

    function _expectEthereumOftEmit(uint256 amount) internal {
        vm.expectEmit(false, true, true, true, address(usdtOft));
        emit OFTSent(bytes32(0), destinationEndpointId, address(almProxy), amount, amount);
    }

    function _expectPlasmaOftEmit(uint256 amount) internal {
        vm.expectEmit(false, true, true, true, address(usdt0OftPlasma));
        emit OFTSent(bytes32(0), sourceEndpointId, address(foreignAlmProxy), amount, amount);
    }
}
