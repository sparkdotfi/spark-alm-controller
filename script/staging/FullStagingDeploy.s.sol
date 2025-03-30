// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    AllocatorDeploy,
    AllocatorIlkInstance,
    AllocatorSharedInstance
} from "dss-allocator/deploy/AllocatorDeploy.sol";

import {
    BufferLike,
    RegistryLike,
    RolesLike,
    VaultLike
} from "dss-allocator/deploy/AllocatorInit.sol";

import { AllocatorBuffer } from "dss-allocator/src/AllocatorBuffer.sol";
import { AllocatorVault }  from "dss-allocator/src/AllocatorVault.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { IERC20 }  from "forge-std/interfaces/IERC20.sol";
import { Script }  from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import {
    ControllerInstance,
    ForeignController,
    ForeignControllerDeploy,
    MainnetController,
    MainnetControllerDeploy
} from "../../deploy/ControllerDeploy.sol";

import { ForeignControllerInit } from "../../deploy/ForeignControllerInit.sol";
import { MainnetControllerInit } from "../../deploy/MainnetControllerInit.sol";

import { IRateLimits } from "../../src/interfaces/IRateLimits.sol";

import { RateLimitHelpers, RateLimitData } from "../../src/RateLimitHelpers.sol";

import { MockJug }          from "./mocks/MockJug.sol";
import { MockUsdsJoin }     from "./mocks/MockUsdsJoin.sol";
import { MockVat }          from "./mocks/MockVat.sol";
import { PSMWrapper }       from "./mocks/PSMWrapper.sol";

struct Domain {
    string  name;
    string  nameDeps;
    string  config;
    uint256 forkId;
    address admin;
}

contract FullStagingDeploy is Script {

    using stdJson     for string;
    using ScriptTools for string;

    /**********************************************************************************************/
    /*** Deployed contracts                                                                     ***/
    /**********************************************************************************************/

    address constant AUSDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    address constant AUSDC_BASE             = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant MORPHO_BASE            = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant MORPHO_VAULT_USDC_BASE = 0x305E03Ed9ADaAB22F4A58c24515D79f2B1E2FD5D;

    /**********************************************************************************************/
    /*** Mainnet existing/mock deployments                                                      ***/
    /**********************************************************************************************/

    address dai;
    address daiUsds;
    address livePsm;
    address psm;
    address susds;
    address usds;
    address usdc;

    // Mocked MCD contracts
    address jug;
    address usdsJoin;
    address vat;

    /**********************************************************************************************/
    /*** Mainnet allocation system deployments                                                  ***/
    /**********************************************************************************************/

    address oracle;
    address roles;
    address registry;

    address buffer;
    address vault;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    address baseAlmProxy;
    address baseController;

    address mainnetAlmProxy;
    address mainnetController;

    /**********************************************************************************************/
    /*** Deployment-specific variables                                                          ***/
    /**********************************************************************************************/

    address deployer;
    bytes32 ilk;

    uint256 USDC_UNIT_SIZE;
    uint256 USDS_UNIT_SIZE;

    Domain mainnet;
    Domain base;

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _setUpDependencies() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Step 1: Use existing contracts for tokens, DaiUsds and PSM

        dai     = mainnet.config.readAddress(".dai");
        usds    = mainnet.config.readAddress(".usds");
        susds   = mainnet.config.readAddress(".susds");
        usdc    = mainnet.config.readAddress(".usdc");
        daiUsds = mainnet.config.readAddress(".daiUsds");
        livePsm = mainnet.config.readAddress(".psm");

        // This contract is necessary to get past the `kiss` requirement from the pause proxy.
        // It wraps the `noFee` calls with regular PSM swap calls.
        psm = address(new PSMWrapper(usdc, dai, livePsm));

        // NOTE: This is a HACK to make sure that `fill` doesn't get called until the call reverts.
        //       Because this PSM contract is a wrapper over the real PSM, the controller queries
        //       the DAI balance of the PSM to check if it should fill or not. Filling with DAI
        //       fills the live PSM NOT the wrapper, so the while loop will continue until the
        //       function reverts. Dealing DAI into the wrapper will prevent fill from being called.
        IERC20(dai).transfer(psm, USDS_UNIT_SIZE);

        // Step 2: Deploy mocked MCD contracts

        vat      = address(new MockVat(mainnet.admin));
        usdsJoin = address(new MockUsdsJoin(mainnet.admin, vat, usds));
        jug      = address(new MockJug());

        // Step 3: Transfer USDS into the join contract

        require(IERC20(usds).balanceOf(deployer) >= USDS_UNIT_SIZE, "USDS balance too low");

        IERC20(usds).transfer(usdsJoin, USDS_UNIT_SIZE);

        vm.stopBroadcast();

        // Step 4: Export all deployed addresses

        ScriptTools.exportContract(mainnet.nameDeps, "dai",      dai);
        ScriptTools.exportContract(mainnet.nameDeps, "daiUsds",  daiUsds);
        ScriptTools.exportContract(mainnet.nameDeps, "jug",      jug);
        ScriptTools.exportContract(mainnet.nameDeps, "psm",      psm);
        ScriptTools.exportContract(mainnet.nameDeps, "susds",    susds);
        ScriptTools.exportContract(mainnet.nameDeps, "usdc",     usdc);
        ScriptTools.exportContract(mainnet.nameDeps, "usds",     usds);
        ScriptTools.exportContract(mainnet.nameDeps, "usdsJoin", usdsJoin);
        ScriptTools.exportContract(mainnet.nameDeps, "vat",      vat);
    }

    function _setUpAllocationSystem() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Step 1: Deploy allocation system

        AllocatorSharedInstance memory allocatorSharedInstance
            = AllocatorDeploy.deployShared(deployer, mainnet.admin);

        AllocatorIlkInstance memory allocatorIlkInstance = AllocatorDeploy.deployIlk(
            deployer,
            mainnet.admin,
            allocatorSharedInstance.roles,
            ilk,
            usdsJoin
        );

        oracle   = allocatorSharedInstance.oracle;
        registry = allocatorSharedInstance.registry;
        roles    = allocatorSharedInstance.roles;

        buffer = allocatorIlkInstance.buffer;
        vault  = allocatorIlkInstance.vault;

        // Step 2: Perform partial initialization (not using library because of mocked MCD)

        RegistryLike(registry).file(ilk, "buffer", buffer);
        VaultLike(vault).file("jug", jug);
        BufferLike(buffer).approve(usds, vault, type(uint256).max);
        RolesLike(roles).setIlkAdmin(ilk, mainnet.admin);

        // Step 3: Move ownership of both the vault and buffer to the admin

        ScriptTools.switchOwner(vault,  allocatorIlkInstance.owner, mainnet.admin);
        ScriptTools.switchOwner(buffer, allocatorIlkInstance.owner, mainnet.admin);

        vm.stopBroadcast();

        // Step 4: Export all deployed addresses

        ScriptTools.exportContract(mainnet.nameDeps, "allocatorOracle",   oracle);
        ScriptTools.exportContract(mainnet.nameDeps, "allocatorRegistry", registry);
        ScriptTools.exportContract(mainnet.nameDeps, "allocatorRoles",    roles);

        ScriptTools.exportContract(mainnet.nameDeps, "allocatorBuffer", buffer);
        ScriptTools.exportContract(mainnet.nameDeps, "allocatorVault",  vault);
    }

    function _setUpMainnetController() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        ControllerInstance memory controllerInst = MainnetControllerDeploy.deployFull({
            admin   : mainnet.admin,
            vault   : vault,
            psm     : psm,  // Wrapper
            daiUsds : daiUsds,
            cctp    : mainnet.config.readAddress(".cctpTokenMessenger")
        });

        mainnetAlmProxy   = controllerInst.almProxy;
        mainnetController = controllerInst.controller;

        // Step 2: Initialize ALM system

        MainnetControllerInit.ConfigAddressParams memory configAddresses 
            = MainnetControllerInit.ConfigAddressParams({
                freezer       : mainnet.config.readAddress(".freezer"),
                relayer       : mainnet.config.readAddress(".relayer"),
                oldController : address(0)
            });

        MainnetControllerInit.CheckAddressParams memory checkAddresses
            = MainnetControllerInit.CheckAddressParams({
                admin      : mainnet.admin,
                proxy      : controllerInst.almProxy,
                rateLimits : controllerInst.rateLimits,
                vault      : vault,
                psm        : psm,
                daiUsds    : mainnet.config.readAddress(".daiUsds"),
                cctp       : mainnet.config.readAddress(".cctpTokenMessenger")
            });

        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](0);

        MainnetControllerInit.initAlmSystem(
            vault,
            address(usds),
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients
        );

        // Step 3: Set all rate limits for the controller

        _setMainnetControllerRateLimits(controllerInst.rateLimits);
        
        // Step 4: Transfer ownership of mock usdsJoin to the vault (able to mint usds)

        MockUsdsJoin(usdsJoin).transferOwnership(vault);

        vm.stopBroadcast();

        // Step 5: Export all deployed addresses

        ScriptTools.exportContract(mainnet.nameDeps, "freezer", mainnet.config.readAddress(".freezer"));
        ScriptTools.exportContract(mainnet.nameDeps, "relayer", mainnet.config.readAddress(".relayer"));

        ScriptTools.exportContract(mainnet.name, "almProxy",   controllerInst.almProxy);
        ScriptTools.exportContract(mainnet.name, "controller", controllerInst.controller);
        ScriptTools.exportContract(mainnet.name, "rateLimits", controllerInst.rateLimits);
    }

    function _setMainnetControllerRateLimits(address rateLimits) internal {
        // Still constrained by the USDC_UNIT_SIZE
        RateLimitData memory rateLimitData18 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 1e12 * 5,
            slope     : USDC_UNIT_SIZE * 1e12 / 4 hours
        });
        RateLimitData memory rateLimitData6 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 5,
            slope     : USDC_UNIT_SIZE / 4 hours
        });

        RateLimitData memory unlimitedRateLimit = RateLimitHelpers.unlimitedRateLimit();

        MainnetController mainnetController_ = MainnetController(mainnetController);

        bytes32 ausdcDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_AAVE_DEPOSIT(),   AUSDC);
        bytes32 ausdcWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_AAVE_WITHDRAW(),  AUSDC);
        bytes32 ausdsDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_AAVE_DEPOSIT(),   AUSDS);
        bytes32 ausdsWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_AAVE_WITHDRAW(),  AUSDS);
        bytes32 susdeDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_4626_DEPOSIT(),   address(mainnetController_.susde()));
        bytes32 susdsDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_4626_DEPOSIT(),   susds);
        bytes32 susdsWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController_.LIMIT_4626_WITHDRAW(),  susds);

        bytes32 domainKeyBase = RateLimitHelpers.makeDomainKey(mainnetController_.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        // USDS mint/burn and cross-chain transfer rate limits
        RateLimitHelpers.setRateLimitData(domainKeyBase,                           rateLimits, rateLimitData6,     "cctpToBaseDomainData", 6);
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_USDC_TO_CCTP(), rateLimits, unlimitedRateLimit, "usdsToCctpData",       6);
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_USDS_MINT(),    rateLimits, rateLimitData18,    "usdsMintData",         18);
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_USDS_TO_USDC(), rateLimits, rateLimitData6,     "usdsToUsdcData",       6);

        // Ethena-specific rate limits
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_SUSDE_COOLDOWN(), rateLimits, rateLimitData18, "susdeCooldownData", 18);
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_USDE_BURN(),      rateLimits, rateLimitData18, "usdeBurnData",      18);
        RateLimitHelpers.setRateLimitData(mainnetController_.LIMIT_USDE_MINT(),      rateLimits, rateLimitData6,  "usdeMintData",      6);

        // 4626 and AAVE deposit/withdraw rate limits
        RateLimitHelpers.setRateLimitData(ausdcDepositKey,  rateLimits, rateLimitData6,     "ausdcDepositData",  6);
        RateLimitHelpers.setRateLimitData(ausdcWithdrawKey, rateLimits, unlimitedRateLimit, "ausdcWithdrawData", 6);
        RateLimitHelpers.setRateLimitData(ausdsDepositKey,  rateLimits, rateLimitData18,    "ausdsDepositData",  18);
        RateLimitHelpers.setRateLimitData(ausdsWithdrawKey, rateLimits, unlimitedRateLimit, "ausdcWithdrawData", 18);
        RateLimitHelpers.setRateLimitData(susdeDepositKey,  rateLimits, rateLimitData18,    "susdeDepositData",  18);
        RateLimitHelpers.setRateLimitData(susdsDepositKey,  rateLimits, unlimitedRateLimit, "susdsDepositData",  18);
        RateLimitHelpers.setRateLimitData(susdsWithdrawKey, rateLimits, unlimitedRateLimit, "susdsWithdrawData", 18);
    }

    function _setBaseControllerRateLimits(address rateLimits) internal {
        RateLimitData memory rateLimitData18 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 1e12 * 5,
            slope     : USDC_UNIT_SIZE * 1e12 / 4 hours
        });
        RateLimitData memory rateLimitData6 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 5,
            slope     : USDC_UNIT_SIZE / 4 hours
        });
        RateLimitData memory unlimitedRateLimit = RateLimitHelpers.unlimitedRateLimit();

        ForeignController foreignController = ForeignController(baseController);

        bytes32 aaveDepositKey   = foreignController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey  = foreignController.LIMIT_AAVE_WITHDRAW();
        bytes32 psmDepositKey    = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey   = foreignController.LIMIT_PSM_WITHDRAW();
        bytes32 vaultDepositKey  = foreignController.LIMIT_4626_DEPOSIT();
        bytes32 vaultWithdrawKey = foreignController.LIMIT_4626_WITHDRAW();
        
        bytes32 domainKeyEthereum = RateLimitHelpers.makeDomainKey(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        usdc  = base.config.readAddress(".usdc");
        usds  = base.config.readAddress(".usds");
        susds = base.config.readAddress(".susds");

        // PSM rate limits for all three assets
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmDepositKey,  usdc),  rateLimits, rateLimitData6,     "usdcDepositDataPsm",   6);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmWithdrawKey, usdc),  rateLimits, rateLimitData6,     "usdcWithdrawDataPsm",  6);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmDepositKey,  usds),  rateLimits, rateLimitData18,    "usdsDepositDataPsm",   18);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmWithdrawKey, usds),  rateLimits, unlimitedRateLimit, "usdsWithdrawDataPsm",  18);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmDepositKey,  susds), rateLimits, rateLimitData18,    "susdsDepositDataPsm",  18);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(psmWithdrawKey, susds), rateLimits, unlimitedRateLimit, "susdsWithdrawDataPsm", 18);

        // CCTP rate limits
        RateLimitHelpers.setRateLimitData(domainKeyEthereum,                      rateLimits, rateLimitData6,     "cctpToEthereumDomainData", 6);
        RateLimitHelpers.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(), rateLimits, unlimitedRateLimit, "usdsToCctpData",           6);

        // AAVE rate limits
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(aaveDepositKey,  AUSDC_BASE), rateLimits, rateLimitData6,     "usdcDepositDataAave",  6);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(aaveWithdrawKey, AUSDC_BASE), rateLimits, unlimitedRateLimit, "usdcWithdrawDataAave", 6);
        
        // Morpho rate limits
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(vaultDepositKey,  MORPHO_VAULT_USDC_BASE), rateLimits, rateLimitData6,     "usdsDepositDataMorpho",  6);
        RateLimitHelpers.setRateLimitData(RateLimitHelpers.makeAssetKey(vaultWithdrawKey, MORPHO_VAULT_USDC_BASE), rateLimits, unlimitedRateLimit, "usdsWithdrawDataMorpho", 6);
    }

    function _setUpBaseALMController() internal {
        vm.selectFork(base.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin : base.admin,
            psm   : base.config.readAddress(".psm"),
            usdc  : base.config.readAddress(".usdc"),
            cctp  : base.config.readAddress(".cctpTokenMessenger")
        });

        baseAlmProxy   = controllerInst.almProxy;
        baseController = controllerInst.controller;

        // Step 2: Initialize ALM system

        ForeignControllerInit.ConfigAddressParams memory configAddresses = ForeignControllerInit.ConfigAddressParams({
            freezer       : base.config.readAddress(".freezer"),
            relayer       : base.config.readAddress(".relayer"),
            oldController : address(0)
        });

        ForeignControllerInit.CheckAddressParams memory checkAddresses = ForeignControllerInit.CheckAddressParams({
            admin : base.admin,
            psm   : base.config.readAddress(".psm"),
            cctp  : base.config.readAddress(".cctpTokenMessenger"),
            usdc  : base.config.readAddress(".usdc"),
            susds : base.config.readAddress(".susds"),
            usds  : base.config.readAddress(".usds")
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(mainnetAlmProxy)))
        });

        ForeignControllerInit.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients
        );

        // Step 3: Set all rate limits for the controller

        _setBaseControllerRateLimits(controllerInst.rateLimits);

        vm.stopBroadcast();

        // Step 4: Export all deployed addresses

        ScriptTools.exportContract(base.nameDeps, "freezer", base.config.readAddress(".freezer"));
        ScriptTools.exportContract(base.nameDeps, "relayer", base.config.readAddress(".relayer"));

        ScriptTools.exportContract(base.name, "almProxy",   controllerInst.almProxy);
        ScriptTools.exportContract(base.name, "controller", controllerInst.controller);
        ScriptTools.exportContract(base.name, "rateLimits", controllerInst.rateLimits);
    }

    function _setBaseMintRecipient() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        MainnetController(mainnetController).setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(baseAlmProxy)))
        );

        vm.stopBroadcast();
    }

    function run() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        deployer = msg.sender;

        mainnet = Domain({
            name     : "mainnet-staging",
            nameDeps : "mainnet-staging-deps",
            config   : ScriptTools.loadConfig("mainnet-staging"),
            forkId   : vm.createFork(getChain("mainnet").rpcUrl),
            admin    : deployer
        });
        base = Domain({
            name     : "base-staging",
            nameDeps : "base-staging-deps",
            config   : ScriptTools.loadConfig("base-staging"),
            forkId :   vm.createFork(getChain("base").rpcUrl),
            admin    : deployer
        });

        // Ballpark sizing of rate limits, tokens in PSMs, etc
        // Ballpark sizing of USDS to put in the join contracts, PSMs, etc
        USDC_UNIT_SIZE = mainnet.config.readUint(".usdcUnitSize") * 1e6;
        USDS_UNIT_SIZE = mainnet.config.readUint(".usdsUnitSize") * 1e18;

        // Run deployment scripts after setting storage variables

        _setUpDependencies();
        _setUpAllocationSystem();
        _setUpMainnetController();
        _setUpBaseALMController();
        _setBaseMintRecipient();

        ScriptTools.exportContract(mainnet.nameDeps, "admin", deployer);
        ScriptTools.exportContract(base.nameDeps,    "admin", deployer);
    }

}
