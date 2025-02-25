// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Test.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { Usds } from "usds/src/Usds.sol";

import { SUsds } from "sdai/src/SUsds.sol";

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { PSM3 } from "spark-psm/src/PSM3.sol";

import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { MainnetControllerDeploy } from "../../../deploy/ControllerDeploy.sol";
import { MainnetControllerInit }   from "../../../deploy/MainnetControllerInit.sol";

import { IRateLimits } from "../../../src/interfaces/IRateLimits.sol";

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";
import { RateLimits }        from "../../../src/RateLimits.sol";

import { RateLimitHelpers }  from "../../../src/RateLimitHelpers.sol";

interface IVatLike {
    function can(address, address) external view returns (uint256);
}

contract StagingDeploymentTestBase is Test {

    using stdJson           for *;
    using DomainHelpers     for *;
    using CCTPBridgeTesting for *;
    using ScriptTools       for *;

    // AAVE aTokens for testing
    address constant AUSDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 constant RELEASE_DATE = 20241227;

    // Common variables
    address admin;

    // Configuration data
    string inputBase;
    string inputMainnet;
    string outputBase;
    string outputBaseDeps;
    string outputMainnet;
    string outputMainnetDeps;

    // Bridging
    Domain mainnet;
    Domain base;
    Bridge cctpBridge;

    // Mainnet contracts

    Usds   usds;
    SUsds  susds;
    IERC20 usdc;
    IERC20 dai;

    address vault;
    address relayerSafe;
    address usdsJoin;

    ALMProxy          almProxy;
    MainnetController mainnetController;
    RateLimits        rateLimits;

    // Base contracts

    address relayerSafeBase;

    PSM3 psmBase;

    IERC20 usdsBase;
    IERC20 susdsBase;
    IERC20 usdcBase;

    ALMProxy          baseAlmProxy;
    ForeignController baseController;
    RateLimits        baseRateLimits;

    /**********************************************************************************************/
    /**** Setup                                                                                 ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        // Domains and bridge
        mainnet    = getChain("mainnet").createSelectFork(21600000);  // Jan 11, 2025
        base       = getChain("base").createFork(24900000);           // Jan 11, 2025
        cctpBridge = CCTPBridgeTesting.createCircleBridge(mainnet, base);

        // JSON data
        inputBase    = ScriptTools.readInput("base-staging");
        inputMainnet = ScriptTools.readInput("mainnet-staging");

        outputBase        = ScriptTools.readOutput("base-staging-release",         RELEASE_DATE);
        outputBaseDeps    = ScriptTools.readOutput("base-staging-deps-release",    RELEASE_DATE);
        outputMainnet     = ScriptTools.readOutput("mainnet-staging-release",      RELEASE_DATE);
        outputMainnetDeps = ScriptTools.readOutput("mainnet-staging-deps-release", RELEASE_DATE);

        // Roles
        admin       = outputMainnetDeps.readAddress(".admin");
        relayerSafe = outputMainnetDeps.readAddress(".relayer");

        // Tokens
        usds  = Usds(outputMainnetDeps.readAddress(".usds"));
        susds = SUsds(outputMainnetDeps.readAddress(".susds"));
        usdc  = IERC20(outputMainnetDeps.readAddress(".usdc"));
        dai   = IERC20(outputMainnetDeps.readAddress(".dai"));

        // Dependencies
        vault    = outputMainnetDeps.readAddress(".allocatorVault");
        usdsJoin = outputMainnetDeps.readAddress(".usdsJoin");

        // ALM system
        almProxy          = ALMProxy(payable(outputMainnet.readAddress(".almProxy")));
        rateLimits        = RateLimits(outputMainnet.readAddress(".rateLimits"));
        mainnetController = MainnetController(outputMainnet.readAddress(".controller"));

        // Base roles
        relayerSafeBase = outputBaseDeps.readAddress(".relayer");

        // Base tokens
        usdsBase  = IERC20(inputBase.readAddress(".usds"));
        susdsBase = IERC20(inputBase.readAddress(".susds"));
        usdcBase  = IERC20(inputBase.readAddress(".usdc"));

        // Base ALM system
        baseAlmProxy   = ALMProxy(payable(outputBase.readAddress(".almProxy")));
        baseController = ForeignController(outputBase.readAddress(".controller"));
        baseRateLimits = RateLimits(outputBase.readAddress(".rateLimits"));

        // Base PSM
        psmBase = PSM3(inputBase.readAddress(".psm"));

        mainnet.selectFork();

        deal(address(usds), address(usdsJoin), 1000e18);  // Ensure there is enough balance
    }
}

contract MainnetStagingDeploymentTests is StagingDeploymentTestBase {

    function test_mintUSDS() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.prank(relayerSafe);
        mainnetController.mintUSDS(10e18);

        assertEq(usds.balanceOf(address(almProxy)), startingBalance + 10e18);
    }

    function test_mintAndSwapToUSDC() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(almProxy)), startingBalance + 10e6);
    }

    function test_depositAndWithdrawUsdsFromSUsds() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10e18);
        skip(1 days);
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 10e18);
        vm.stopPrank();

        assertEq(usds.balanceOf(address(almProxy)), startingBalance + 10e18);  

        assertGe(IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)), 0);  // Interest earned
    }

    function test_depositAndRedeemUsdsFromSUsds() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10e18);
        skip(1 days);
        mainnetController.redeemERC4626(Ethereum.SUSDS, IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)));
        vm.stopPrank();

        assertGe(usds.balanceOf(address(almProxy)), startingBalance + 10e18);  // Interest earned

        assertEq(IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)), 0);  
    }

    function test_depositAndWithdrawUsdsFromAave() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.depositAave(AUSDS, 10e6);
        skip(1 days);
        mainnetController.withdrawAave(AUSDS, type(uint256).max);
        vm.stopPrank();

        assertGe(usds.balanceOf(address(almProxy)), startingBalance + 10e6);  // Interest earned
    }

    function test_depositAndWithdrawUsdcFromAave() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.depositAave(AUSDC, 10e6);
        skip(1 days);
        mainnetController.withdrawAave(AUSDC, type(uint256).max);
        vm.stopPrank();

        assertGe(usdc.balanceOf(address(almProxy)), startingBalance + 10e6);  // Interest earned
    }

    function test_mintDepositCooldownAssetsBurnUsde() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.prepareUSDeMint(10e6);
        vm.stopPrank();

        _simulateUsdeMint(10e6);

        vm.startPrank(relayerSafe);
        mainnetController.depositERC4626(Ethereum.SUSDE, 10e18);
        skip(1 days);
        mainnetController.cooldownAssetsSUSDe(10e18 - 1);  // Rounding
        skip(7 days);
        mainnetController.unstakeSUSDe();
        mainnetController.prepareUSDeBurn(10e18 - 1);
        vm.stopPrank();

        _simulateUsdeBurn(10e18 - 1);

        assertEq(usdc.balanceOf(address(almProxy)), startingBalance + 10e6 - 1);  // Rounding not captured 
        
        assertGe(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)), 0);  // Interest earned
    }

    function test_mintDepositCooldownSharesBurnUsde() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.prepareUSDeMint(10e6);
        vm.stopPrank();

        _simulateUsdeMint(10e6);

        vm.startPrank(relayerSafe);
        mainnetController.depositERC4626(Ethereum.SUSDE, 10e18);
        skip(1 days);
        uint256 usdeAmount = mainnetController.cooldownSharesSUSDe(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)));
        skip(7 days);
        mainnetController.unstakeSUSDe();
        mainnetController.prepareUSDeBurn(usdeAmount);
        vm.stopPrank();

        _simulateUsdeBurn(usdeAmount);

        assertGe(usdc.balanceOf(address(almProxy)), startingBalance + 10e6 - 1);  // Interest earned (rounding)
        
        assertEq(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)), 0);  
    }

    /**********************************************************************************************/
    /**** Helper functions                                                                      ***/
    /**********************************************************************************************/

    // NOTE: In reality these actions are performed by the signer submitting an order with an 
    //       EIP712 signature which is verified by the ethenaMinter contract, 
    //       minting/burning USDe into the ALMProxy. Also, for the purposes of this test, 
    //       minting/burning is done 1:1 with USDC.

    // TODO: Try doing ethena minting with EIP-712 signatures (vm.sign)

    function _simulateUsdeMint(uint256 amount) internal {
        vm.prank(Ethereum.ETHENA_MINTER);
        usdc.transferFrom(address(almProxy), Ethereum.ETHENA_MINTER, amount);
        deal(
            Ethereum.USDE, 
            address(almProxy), 
            IERC20(Ethereum.USDE).balanceOf(address(almProxy)) + amount * 1e12
        );
    }

    function _simulateUsdeBurn(uint256 amount) internal {
        vm.prank(Ethereum.ETHENA_MINTER);
        IERC20(Ethereum.USDE).transferFrom(address(almProxy), Ethereum.ETHENA_MINTER, amount);
        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount / 1e12);
    }

}

contract BaseStagingDeploymentTests is StagingDeploymentTestBase {

    using DomainHelpers     for *;
    using CCTPBridgeTesting for *;

    address constant AUSDC_BASE        = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant MORPHO            = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant MORPHO_VAULT_USDC = 0x305E03Ed9ADaAB22F4A58c24515D79f2B1E2FD5D;

    function setUp() public override {
        super.setUp();

        base.selectFork();
    }

    function test_transferCCTP() public {
        base.selectFork();

        uint256 startingBalance = usdcBase.balanceOf(address(baseAlmProxy));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), startingBalance + 10e6);
    }

    function test_transferToPSM() public {
        base.selectFork();

        uint256 startingBalance = usdcBase.balanceOf(address(psmBase));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        uint256 startingShares = psmBase.shares(address(baseAlmProxy));

        vm.startPrank(relayerSafeBase);
        baseController.depositPSM(address(usdcBase), 10e6);
        vm.stopPrank();

        assertEq(usdcBase.balanceOf(address(psmBase)), startingBalance + 10e6);

        assertEq(psmBase.shares(address(baseAlmProxy)), startingShares + psmBase.convertToShares(10e18));
    }

    function test_addAndRemoveFundsFromBasePSM() public {
        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositPSM(address(usdcBase), 10e6);
        skip(1 days);
        baseController.withdrawPSM(address(usdcBase), 10e6);
        baseController.transferUSDCToCCTP(10e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridge.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(10e6 - 1);
        mainnetController.burnUSDS((10e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_addAndRemoveFundsFromBaseAAVE() public {
        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositAave(AUSDC_BASE, 10e6);
        skip(1 days);
        baseController.withdrawAave(AUSDC_BASE, 10e6);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);

        assertGe(IERC20(AUSDC_BASE).balanceOf(address(baseAlmProxy)), 0);  // Interest earned

        baseController.transferUSDCToCCTP(10e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridge.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(10e6 - 1);
        mainnetController.burnUSDS((10e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_depositWithdrawFundsFromBaseMorphoUsdc() public {
        _setUpMorphoMarket();

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositERC4626(MORPHO_VAULT_USDC, 10e6);
        skip(1 days);
        baseController.withdrawERC4626(MORPHO_VAULT_USDC, 10e6);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);

        assertGe(IERC20(MORPHO_VAULT_USDC).balanceOf(address(baseAlmProxy)), 0);  // Interest earned

        baseController.transferUSDCToCCTP(1e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridge.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(1e6 - 1);
        mainnetController.burnUSDS((1e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_depositRedeemFundsFromBaseMorphoUsdc() public {
        _setUpMorphoMarket();

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridge.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositERC4626(MORPHO_VAULT_USDC, 10e6);
        skip(1 days);
        baseController.redeemERC4626(MORPHO_VAULT_USDC, IERC20(MORPHO_VAULT_USDC).balanceOf(address(baseAlmProxy)));

        assertGe(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);  // Interest earned

        assertEq(IERC20(MORPHO_VAULT_USDC).balanceOf(address(baseAlmProxy)), 0);  

        baseController.transferUSDCToCCTP(1e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridge.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(1e6 - 1);
        mainnetController.burnUSDS((1e6 - 1) * 1e12);
        vm.stopPrank();
    }

    // TODO: Replace this once market is live
    function _setUpMorphoMarket() public {
        vm.startPrank(Base.SPARK_EXECUTOR);

        // Add in the idle markets so deposits can be made
        MarketParams memory usdcParams = MarketParams({
            loanToken       : Base.USDC,
            collateralToken : address(0),
            oracle          : address(0),
            irm             : address(0),
            lltv            : 0
        });

        IMetaMorpho(MORPHO_VAULT_USDC).submitCap(
            usdcParams,
            type(uint184).max
        );

        skip(1 days);

        IMetaMorpho(MORPHO_VAULT_USDC).acceptCap(usdcParams);

        Id[] memory supplyQueueUSDC = new Id[](1);
        supplyQueueUSDC[0] = MarketParamsLib.id(usdcParams);
        IMetaMorpho(MORPHO_VAULT_USDC).setSupplyQueue(supplyQueueUSDC);

        vm.stopPrank();
    }

}
