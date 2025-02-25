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

import { CCTPForwarder } from "xchain-helpers/src/forwarders/CCTPForwarder.sol";

import {
    ControllerInstance,
    ForeignController,
    ForeignControllerDeploy,
    MainnetController,
    MainnetControllerDeploy
} from "../../deploy/ControllerDeploy.sol";

import {
    ForeignControllerInit,
    MainnetControllerInit,
    MintRecipient,
    RateLimitData
} from "../../deploy/ControllerInit.sol";

import { IRateLimits }      from "../../src/interfaces/IRateLimits.sol";
import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

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

    function _setUpALMController() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        ControllerInstance memory instance = MainnetControllerDeploy.deployFull({
            admin   : mainnet.admin,
            vault   : vault,
            psm     : psm,
            daiUsds : daiUsds,
            cctp    : mainnet.config.readAddress(".cctpTokenMessenger")
        });

        mainnetAlmProxy   = instance.almProxy;
        mainnetController = instance.controller;

        // Step 2: Initialize ALM controller, setting rate limits, mint recipients, and setting ACL

        // Still constrained by the USDC_UNIT_SIZE
        RateLimitData memory rateLimitData18 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 1e12 * 5,
            slope     : USDC_UNIT_SIZE * 1e12 / 4 hours
        });
        RateLimitData memory rateLimitData6 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 5,
            slope     : USDC_UNIT_SIZE / 4 hours
        });
        RateLimitData memory unlimitedRateLimit = RateLimitData({
            maxAmount : type(uint256).max,
            slope     : 0
        });

        // Configure this after Base ALM Proxy is deployed
        MintRecipient[] memory mintRecipients = new MintRecipient[](0);

        MainnetControllerInit.subDaoInitFull({
            addresses: MainnetControllerInit.AddressParams({
                admin         : mainnet.admin,
                freezer       : mainnet.config.readAddress(".freezer"),
                relayer       : mainnet.config.readAddress(".relayer"),
                oldController : address(0),
                psm           : psm,
                vault         : vault,
                buffer        : buffer,
                cctpMessenger : mainnet.config.readAddress(".cctpTokenMessenger"),
                dai           : dai,
                daiUsds       : daiUsds,
                usdc          : usdc,
                usds          : usds,
                susds         : susds
            }),
            controllerInst: instance,
            data: MainnetControllerInit.InitRateLimitData({
                usdsMintData         : rateLimitData18,
                usdsToUsdcData       : rateLimitData6,
                usdcToCctpData       : unlimitedRateLimit,
                cctpToBaseDomainData : rateLimitData6,
                susdsDepositData     : rateLimitData18
            }),
            mintRecipients: mintRecipients
        });

        // Extra rate limit configuration
        bytes32 mintKey = MainnetController(instance.controller).LIMIT_USDE_MINT();
        bytes32 burnKey = MainnetController(instance.controller).LIMIT_USDE_BURN();

        bytes32 susdsDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(instance.controller).LIMIT_4626_DEPOSIT(),
            address(MainnetController(instance.controller).susde())
        );

        bytes32 susdsWithdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(instance.controller).LIMIT_4626_WITHDRAW(),
            address(MainnetController(instance.controller).susde())
        );

        // Extra rate limit configuration
        MainnetControllerInit.setRateLimitData(mintKey,          IRateLimits(instance.rateLimits), rateLimitData6,  "usdeMintData",      6);
        MainnetControllerInit.setRateLimitData(burnKey,          IRateLimits(instance.rateLimits), rateLimitData18, "usdeBurnData",      18);
        MainnetControllerInit.setRateLimitData(susdsDepositKey,  IRateLimits(instance.rateLimits), rateLimitData18, "susdsDepositData",  18);
        MainnetControllerInit.setRateLimitData(susdsWithdrawKey, IRateLimits(instance.rateLimits), rateLimitData18, "susdsWithdrawData", 18);

        // Step 3: Transfer ownership of mock usdsJoin to the vault (able to mint usds)

        MockUsdsJoin(usdsJoin).transferOwnership(vault);

        vm.stopBroadcast();

        // Step 4: Export all deployed addresses

        ScriptTools.exportContract(mainnet.nameDeps, "freezer",    mainnet.config.readAddress(".freezer"));
        ScriptTools.exportContract(mainnet.nameDeps, "relayer",    mainnet.config.readAddress(".relayer"));

        ScriptTools.exportContract(mainnet.name, "almProxy",   instance.almProxy);
        ScriptTools.exportContract(mainnet.name, "controller", instance.controller);
        ScriptTools.exportContract(mainnet.name, "rateLimits", instance.rateLimits);
    }

    function _setUpBaseALMController() public {
        vm.selectFork(base.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        ControllerInstance memory instance = ForeignControllerDeploy.deployFull({
            admin : base.admin,
            psm   : base.config.readAddress(".psm"),
            usdc  : base.config.readAddress(".usdc"),
            cctp  : base.config.readAddress(".cctpTokenMessenger")
        });

        baseAlmProxy   = instance.almProxy;
        baseController = instance.controller;

        // Step 2: Initialize ALM controller, setting rate limits, mint recipients, and setting ACL

        // Still constrained by the USDC_UNIT_SIZE
        RateLimitData memory rateLimitData18 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 1e12 * 5,
            slope     : USDC_UNIT_SIZE * 1e12 / 4 hours
        });
        RateLimitData memory rateLimitData6 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 5,
            slope     : USDC_UNIT_SIZE / 4 hours
        });
        RateLimitData memory unlimitedRateLimit = RateLimitData({
            maxAmount : type(uint256).max,
            slope     : 0
        });

        MintRecipient[] memory mintRecipients = new MintRecipient[](1);
        mintRecipients[0] = MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(mainnetAlmProxy)))
        });

        ForeignControllerInit.init({
            addresses: ForeignControllerInit.AddressParams({
                admin         : base.admin,
                freezer       : base.config.readAddress(".freezer"),
                relayer       : base.config.readAddress(".relayer"),
                oldController : address(0),
                psm           : base.config.readAddress(".psm"),
                cctpMessenger : base.config.readAddress(".cctpTokenMessenger"),
                usdc          : base.config.readAddress(".usdc"),
                usds          : base.config.readAddress(".usds"),
                susds         : base.config.readAddress(".susds")
            }),
            controllerInst: instance,
            data: ForeignControllerInit.InitRateLimitData({
                usdcDepositData          : rateLimitData6,
                usdcWithdrawData         : rateLimitData6,
                usdsDepositData          : rateLimitData18,
                usdsWithdrawData         : rateLimitData18,
                susdsDepositData         : rateLimitData18,
                susdsWithdrawData        : rateLimitData18,
                usdcToCctpData           : unlimitedRateLimit,
                cctpToEthereumDomainData : rateLimitData6
            }),
            mintRecipients: mintRecipients
        });

        vm.stopBroadcast();

        // Step 3: Export all deployed addresses

        ScriptTools.exportContract(base.nameDeps, "freezer",    base.config.readAddress(".freezer"));
        ScriptTools.exportContract(base.nameDeps, "relayer",    base.config.readAddress(".relayer"));

        ScriptTools.exportContract(base.name, "almProxy",   instance.almProxy);
        ScriptTools.exportContract(base.name, "controller", instance.controller);
        ScriptTools.exportContract(base.name, "rateLimits", instance.rateLimits);
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
            forkId   : vm.createFork(getChain("base").rpcUrl),
            admin    : deployer
        });

        // Ballpark sizing of rate limits, tokens in PSMs, etc
        // Ballpark sizing of USDS to put in the join contracts, PSMs, etc
        USDC_UNIT_SIZE = mainnet.config.readUint(".usdcUnitSize") * 1e6;
        USDS_UNIT_SIZE = mainnet.config.readUint(".usdsUnitSize") * 1e18;

        // Run deployment scripts after setting storage variables

        _setUpDependencies();
        _setUpAllocationSystem();
        _setUpALMController();
        _setUpBaseALMController();
        _setBaseMintRecipient();

        ScriptTools.exportContract(mainnet.nameDeps, "admin", deployer);
        ScriptTools.exportContract(base.nameDeps,    "admin", deployer);
    }

}
