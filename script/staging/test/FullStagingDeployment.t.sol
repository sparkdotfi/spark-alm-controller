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

interface IMapleTokenExtended is IERC4626 {
    function manager() external view returns (address);
}

interface IWithdrawalManagerLike {
    function processRedemptions(uint256 maxSharesToProcess) external;
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (IWithdrawalManagerLike);
    function poolDelegate() external view returns (address);
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
    string inputArbitrum;
    string inputBase;
    string inputMainnet;

    // Bridging
    Domain mainnet;
    Domain arbitrum;
    Domain base;

    Bridge cctpBridgeArbitrum;
    Bridge cctpBridgeBase;

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

    // Arbitrum contracts

    address relayerSafeArbitrum;

    PSM3 psmArbitrum;

    IERC20 usdsArbitrum;
    IERC20 susdsArbitrum;
    IERC20 usdcArbitrum;

    ALMProxy          arbitrumAlmProxy;
    ForeignController arbitrumController;
    RateLimits        arbitrumRateLimits;

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
        mainnet    = getChain("mainnet").createSelectFork(22233941);  // April 9, 2025
        base       = getChain("base").createFork(28721799);           // April 9, 2025
        arbitrum   = getChain("arbitrum_one").createFork(324683441);  // April 9, 2025

        cctpBridgeArbitrum = CCTPBridgeTesting.createCircleBridge(mainnet, arbitrum);
        cctpBridgeBase     = CCTPBridgeTesting.createCircleBridge(mainnet, base);

        // JSON data
        inputArbitrum = ScriptTools.readInput("arbitrum_one-staging");
        inputBase     = ScriptTools.readInput("base-staging");
        inputMainnet  = ScriptTools.readInput("mainnet-staging");

        // --- Mainnet ---

        // Roles
        admin       = inputMainnet.readAddress(".admin");
        relayerSafe = inputMainnet.readAddress(".relayer");

        // Tokens
        usds  = Usds(inputMainnet.readAddress(".usds"));
        susds = SUsds(inputMainnet.readAddress(".susds"));
        usdc  = IERC20(inputMainnet.readAddress(".usdc"));
        dai   = IERC20(inputMainnet.readAddress(".dai"));

        // Dependencies
        vault    = inputMainnet.readAddress(".allocatorVault");
        usdsJoin = inputMainnet.readAddress(".usdsJoin");

        // ALM system
        almProxy          = ALMProxy(payable(inputMainnet.readAddress(".almProxy")));
        rateLimits        = RateLimits(inputMainnet.readAddress(".rateLimits"));
        mainnetController = MainnetController(inputMainnet.readAddress(".controller"));

        // --- Arbitrum ---

        // Roles
        relayerSafeArbitrum = inputArbitrum.readAddress(".relayer");

        // Tokens
        usdsArbitrum  = IERC20(inputArbitrum.readAddress(".usds"));
        susdsArbitrum = IERC20(inputArbitrum.readAddress(".susds"));
        usdcArbitrum  = IERC20(inputArbitrum.readAddress(".usdc"));

        // ALM system
        arbitrumAlmProxy   = ALMProxy(payable(inputArbitrum.readAddress(".almProxy")));
        arbitrumController = ForeignController(inputArbitrum.readAddress(".controller"));
        arbitrumRateLimits = RateLimits(inputArbitrum.readAddress(".rateLimits"));

        // PSM3
        psmArbitrum = PSM3(inputArbitrum.readAddress(".psm"));

        // --- Base ---

        // Roles
        relayerSafeBase = inputBase.readAddress(".relayer");

        // Tokens
        usdsBase  = IERC20(inputBase.readAddress(".usds"));
        susdsBase = IERC20(inputBase.readAddress(".susds"));
        usdcBase  = IERC20(inputBase.readAddress(".usdc"));

        // ALM system
        baseAlmProxy   = ALMProxy(payable(inputBase.readAddress(".almProxy")));
        baseController = ForeignController(inputBase.readAddress(".controller"));
        baseRateLimits = RateLimits(inputBase.readAddress(".rateLimits"));

        // PSM3
        psmBase = PSM3(inputBase.readAddress(".psm"));

        mainnet.selectFork();

        deal(address(usds), address(usdsJoin), 1000e18);  // Ensure there is enough balance
    }
}

contract FullMainnetStagingDeploymentTests is StagingDeploymentTestBase {

    // Remove this to unskip the test base setup
    function setUp() public override {}

    function test_mintUSDS() public {
        vm.skip(true);

        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.prank(relayerSafe);
        mainnetController.mintUSDS(10e18);

        assertEq(usds.balanceOf(address(almProxy)), startingBalance + 10e18);
    }

    function test_mintAndSwapToUSDC() public {
        vm.skip(true);

        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(almProxy)), startingBalance + 10e6);
    }

    function test_depositAndWithdrawUsdsFromSUsds() public {
        vm.skip(true);

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
        vm.skip(true);

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
        vm.skip(true);

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
        vm.skip(true);

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
        vm.skip(true);

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
        vm.skip(true);

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.prepareUSDeMint(10e6);
        vm.stopPrank();

        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        _simulateUsdeMint(10e6);

        vm.startPrank(relayerSafe);
        mainnetController.depositERC4626(Ethereum.SUSDE, 10e18);
        skip(1 days);
        uint256 usdeAmount = mainnetController.cooldownSharesSUSDe(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)));
        skip(7 days);
        mainnetController.unstakeSUSDe();

        // Handle situation where usde balance of ALM Proxy is higher than max rate limit
        uint256 maxBurnAmount = rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDE_BURN());
        uint256 burnAmount    = usdeAmount > maxBurnAmount ? maxBurnAmount : usdeAmount;
        mainnetController.prepareUSDeBurn(burnAmount);

        vm.stopPrank();

        _simulateUsdeBurn(burnAmount);

        assertGe(usdc.balanceOf(address(almProxy)), startingBalance - 1);  // Interest earned (rounding)

        assertEq(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)), 0);
    }

    // TODO: Get Maple team to whitelist staging almProxy for testing when needed
    // function test_mintDepositWithdrawSyrupUsdc() public {
    //     vm.startPrank(relayerSafe);
    //     mainnetController.mintUSDS(10e18);
    //     mainnetController.swapUSDSToUSDC(10e6);
    //     vm.stopPrank();

    //     uint256 startingBalance = usdc.balanceOf(address(almProxy));

    //     vm.startPrank(relayerSafe);
    //     uint256 shares = mainnetController.depositERC4626(Ethereum.SYRUP_USDC, 10e6);

    //     skip(1 days);

    //     mainnetController.requestMapleRedemption(Ethereum.SYRUP_USDC, shares);

    //     IMapleTokenExtended syrup = IMapleTokenExtended(Ethereum.SYRUP_USDC);

    //     IWithdrawalManagerLike withdrawManager = IPoolManagerLike(syrup.manager()).withdrawalManager();
    //     vm.startPrank(IPoolManagerLike(syrup.manager()).poolDelegate());
    //     withdrawManager.processRedemptions(shares);
    //     vm.stopPrank();

    //     assertGe(usdc.balanceOf(address(almProxy)), startingBalance - 1);  // Interest earned (rounding)
    // }


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

contract FullBaseStagingDeploymentTests is StagingDeploymentTestBase {

    using DomainHelpers     for *;
    using CCTPBridgeTesting for *;

    address constant AUSDC_BASE = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant MORPHO     = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;


    // Remove this  and uncomment setup below to unskip the test base setup
    function setUp() public override {}

    // function setUp() public override {
    //     super.setUp();

    //     base.selectFork();
    // }

    function test_transferCCTP() public {
        vm.skip(true);

        base.selectFork();

        uint256 startingBalance = usdcBase.balanceOf(address(baseAlmProxy));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), startingBalance + 10e6);
    }

    function test_transferToPSM() public {
        vm.skip(true);

        base.selectFork();

        uint256 startingBalance = usdcBase.balanceOf(address(psmBase));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        uint256 startingShares = psmBase.shares(address(baseAlmProxy));

        vm.startPrank(relayerSafeBase);
        baseController.depositPSM(address(usdcBase), 10e6);
        vm.stopPrank();

        assertEq(usdcBase.balanceOf(address(psmBase)), startingBalance + 10e6);

        assertEq(psmBase.shares(address(baseAlmProxy)), startingShares + psmBase.convertToShares(10e18));
    }

    function test_addAndRemoveFundsFromBasePSM() public {
        vm.skip(true);

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositPSM(address(usdcBase), 10e6);
        skip(1 days);
        baseController.withdrawPSM(address(usdcBase), 10e6);
        baseController.transferUSDCToCCTP(10e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(10e6 - 1);
        mainnetController.burnUSDS((10e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_addAndRemoveFundsFromBaseAAVE() public {
        vm.skip(true);

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositAave(AUSDC_BASE, 10e6);
        skip(1 days);
        baseController.withdrawAave(AUSDC_BASE, 10e6);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);

        assertGe(IERC20(AUSDC_BASE).balanceOf(address(baseAlmProxy)), 0);  // Interest earned

        baseController.transferUSDCToCCTP(10e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(10e6 - 1);
        mainnetController.burnUSDS((10e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_depositWithdrawFundsFromBaseMorphoUsdc() public {
        vm.skip(true);

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositERC4626(Base.MORPHO_VAULT_SUSDC, 10e6);
        skip(1 days);
        baseController.withdrawERC4626(Base.MORPHO_VAULT_SUSDC, 10e6);

        assertEq(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);

        assertGe(IERC20(Base.MORPHO_VAULT_SUSDC).balanceOf(address(baseAlmProxy)), 0);  // Interest earned

        baseController.transferUSDCToCCTP(1e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(1e6 - 1);
        mainnetController.burnUSDS((1e6 - 1) * 1e12);
        vm.stopPrank();
    }

    function test_depositRedeemFundsFromBaseMorphoUsdc() public {
        vm.skip(true);

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeBase);
        baseController.depositERC4626(Base.MORPHO_VAULT_SUSDC, 10e6);
        skip(1 days);
        baseController.redeemERC4626(Base.MORPHO_VAULT_SUSDC, IERC20(Base.MORPHO_VAULT_SUSDC).balanceOf(address(baseAlmProxy)));

        assertGe(usdcBase.balanceOf(address(baseAlmProxy)), 10e6);  // Interest earned

        assertEq(IERC20(Base.MORPHO_VAULT_SUSDC).balanceOf(address(baseAlmProxy)), 0);

        baseController.transferUSDCToCCTP(1e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridgeBase.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(1e6 - 1);
        mainnetController.burnUSDS((1e6 - 1) * 1e12);
        vm.stopPrank();
    }

}

contract ArbitrumStagingDeploymentTests is StagingDeploymentTestBase {

    using DomainHelpers     for *;
    using CCTPBridgeTesting for *;

    // Remove this  and uncomment setup below to unskip the test base setup
    function setUp() public override {}

    // function setUp() public override {
    //     super.setUp();

    //     arbitrum.selectFork();
    // }

    function test_transferCCTP() public {
        vm.skip(true);

        arbitrum.selectFork();

        uint256 startingBalance = usdcArbitrum.balanceOf(address(arbitrumAlmProxy));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        vm.stopPrank();

        cctpBridgeArbitrum.relayMessagesToDestination(true);

        assertEq(usdcArbitrum.balanceOf(address(arbitrumAlmProxy)), startingBalance + 10e6);
    }

    function test_transferToPSM() public {
        vm.skip(true);

        arbitrum.selectFork();

        uint256 startingBalance = usdcArbitrum.balanceOf(address(psmArbitrum));

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        vm.stopPrank();

        cctpBridgeArbitrum.relayMessagesToDestination(true);

        uint256 startingShares = psmArbitrum.shares(address(arbitrumAlmProxy));

        vm.startPrank(relayerSafeArbitrum);
        arbitrumController.depositPSM(address(usdcArbitrum), 10e6);
        vm.stopPrank();

        assertEq(usdcArbitrum.balanceOf(address(psmArbitrum)), startingBalance + 10e6);

        assertEq(psmArbitrum.shares(address(arbitrumAlmProxy)), startingShares + psmArbitrum.convertToShares(10e18));
    }

    function test_addAndRemoveFundsFromArbitrumPSM() public {
        vm.skip(true);

        mainnet.selectFork();

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.transferUSDCToCCTP(10e6, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        vm.stopPrank();

        cctpBridgeArbitrum.relayMessagesToDestination(true);

        vm.startPrank(relayerSafeArbitrum);
        arbitrumController.depositPSM(address(usdcArbitrum), 10e6);
        skip(1 days);
        arbitrumController.withdrawPSM(address(usdcArbitrum), 10e6);
        arbitrumController.transferUSDCToCCTP(10e6 - 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);  // Account for potential rounding
        vm.stopPrank();

        cctpBridgeArbitrum.relayMessagesToSource(true);

        vm.startPrank(relayerSafe);
        mainnetController.swapUSDCToUSDS(10e6 - 1);
        mainnetController.burnUSDS((10e6 - 1) * 1e12);
        vm.stopPrank();
    }

}
