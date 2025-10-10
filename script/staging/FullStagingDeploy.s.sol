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

import { Base }     from "lib/spark-address-registry/src/Base.sol";
import { Ethereum } from "lib/spark-address-registry/src/Ethereum.sol";

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

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

import { MockJug }          from "./mocks/MockJug.sol";
import { MockUsdsJoin }     from "./mocks/MockUsdsJoin.sol";
import { MockVat }          from "./mocks/MockVat.sol";
import { PSMWrapper }       from "./mocks/PSMWrapper.sol";

struct Domain {
    string  input;
    string  output;
    uint256 forkId;
    address admin;
}

contract FullStagingDeploy is Script {

    using stdJson     for string;
    using ScriptTools for string;

    /**********************************************************************************************/
    /*** Deployed contracts                                                                     ***/
    /**********************************************************************************************/

    address constant AUSDS  = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address constant AUSDC  = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant SPUSDC = Ethereum.USDC_SPTOKEN;  // SparkLend spUSDC

    address constant FLUID_SUSDS_VAULT      = 0x2BBE31d63E6813E3AC858C04dae43FB2a72B0D11;
    address constant FLUID_SUSDS_VAULT_BASE = 0xf62e339f21d8018940f188F6987Bcdf02A849619;

    address constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

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

    ControllerInstance arbitrumInst;
    ControllerInstance baseInst;
    ControllerInstance mainnetInst;

    /**********************************************************************************************/
    /*** Deployment-specific variables                                                          ***/
    /**********************************************************************************************/

    address deployer;
    bytes32 ilk;

    uint256 USDC_UNIT_SIZE;
    uint256 USDS_UNIT_SIZE;

    Domain mainnet;
    Domain arbitrum;
    Domain base;

    uint256 maxAmount18;
    uint256 maxAmount6;
    uint256 slope18;
    uint256 slope6;

    /**********************************************************************************************/
    /*** Mainnet dependency helper functions                                                    ***/
    /**********************************************************************************************/

    function _setUpMainnetDependencies() internal {
        vm.selectFork(mainnet.forkId);

        // Step 1: Use existing contracts for tokens, DaiUsds and PSM

        dai     = mainnet.input.readAddress(".dai");
        usds    = mainnet.input.readAddress(".usds");
        susds   = mainnet.input.readAddress(".susds");
        usdc    = mainnet.input.readAddress(".usdc");
        daiUsds = mainnet.input.readAddress(".daiUsds");
        livePsm = mainnet.input.readAddress(".psm");

        vm.startBroadcast();

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

        // Step 4: Export all dependency addresses

        ScriptTools.exportContract(mainnet.output, "jug",        jug);
        ScriptTools.exportContract(mainnet.output, "psmWrapper", psm);
        ScriptTools.exportContract(mainnet.output, "usdsJoin",   usdsJoin);
        ScriptTools.exportContract(mainnet.output, "vat",        vat);
    }

    function _setUpMainnetAllocationSystem() internal {
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

        ScriptTools.exportContract(mainnet.output, "allocatorOracle",   oracle);
        ScriptTools.exportContract(mainnet.output, "allocatorRegistry", registry);
        ScriptTools.exportContract(mainnet.output, "allocatorRoles",    roles);

        ScriptTools.exportContract(mainnet.output, "allocatorBuffer", buffer);
        ScriptTools.exportContract(mainnet.output, "allocatorVault",  vault);
    }

    /**********************************************************************************************/
    /*** ALM Controller initialization helper functions                                         ***/
    /**********************************************************************************************/

    function _setUpMainnetController() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        mainnetInst = MainnetControllerDeploy.deployFull({
            admin   : mainnet.admin,
            vault   : vault,
            psm     : psm,  // Wrapper
            daiUsds : daiUsds,
            cctp    : mainnet.input.readAddress(".cctpTokenMessenger")
        });

        // Step 2: Initialize ALM system

        address[] memory relayers = new address[](1);
        relayers[0] = mainnet.input.readAddress(".relayer");

        MainnetControllerInit.ConfigAddressParams memory configAddresses
            = MainnetControllerInit.ConfigAddressParams({
                freezer       : mainnet.input.readAddress(".freezer"),
                relayers      : relayers,
                oldController : address(0)
            });

        MainnetControllerInit.CheckAddressParams memory checkAddresses
            = MainnetControllerInit.CheckAddressParams({
                admin      : mainnet.admin,
                proxy      : mainnetInst.almProxy,
                rateLimits : mainnetInst.rateLimits,
                vault      : vault,
                psm        : psm,
                daiUsds    : mainnet.input.readAddress(".daiUsds"),
                cctp       : mainnet.input.readAddress(".cctpTokenMessenger")
            });

        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](0);

        MainnetControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new MainnetControllerInit.LayerZeroRecipient[](0);

        MainnetControllerInit.MaxSlippageParams[] memory maxSlippageParams = new MainnetControllerInit.MaxSlippageParams[](0);

        MainnetControllerInit.initAlmSystem(
            vault,
            address(usds),
            mainnetInst,
            configAddresses,
            checkAddresses,
            mintRecipients,
            layerZeroRecipients,
            maxSlippageParams
        );

        // Step 5: Transfer ownership of mock usdsJoin to the vault (able to mint usds)

        MockUsdsJoin(usdsJoin).transferOwnership(vault);

        vm.stopBroadcast();

        // Step 6: Export all relevant addresses

        ScriptTools.exportContract(mainnet.output, "freezer",    mainnet.input.readAddress(".freezer"));
        ScriptTools.exportContract(mainnet.output, "relayer",    mainnet.input.readAddress(".relayer"));
        ScriptTools.exportContract(mainnet.output, "almProxy",   mainnetInst.almProxy);
        ScriptTools.exportContract(mainnet.output, "controller", mainnetInst.controller);
        ScriptTools.exportContract(mainnet.output, "rateLimits", mainnetInst.rateLimits);
    }

    function _setUpForeignALMController(Domain memory domain) internal returns (ControllerInstance memory controllerInst) {
        vm.selectFork(domain.forkId);
        vm.startBroadcast();

        // Step 1: Deploy ALM controller

        controllerInst = ForeignControllerDeploy.deployFull({
            admin : domain.admin,
            psm   : domain.input.readAddress(".psm"),
            usdc  : domain.input.readAddress(".usdc"),
            cctp  : domain.input.readAddress(".cctpTokenMessenger")
        });

        // Step 2: Initialize ALM system

        address[] memory relayers = new address[](1);
        relayers[0] = domain.input.readAddress(".relayer");

        ForeignControllerInit.ConfigAddressParams memory configAddresses = ForeignControllerInit.ConfigAddressParams({
            freezer       : domain.input.readAddress(".freezer"),
            relayers      : relayers,
            oldController : address(0)
        });

        ForeignControllerInit.CheckAddressParams memory checkAddresses = ForeignControllerInit.CheckAddressParams({
            admin : domain.admin,
            psm   : domain.input.readAddress(".psm"),
            cctp  : domain.input.readAddress(".cctpTokenMessenger"),
            usdc  : domain.input.readAddress(".usdc"),
            susds : domain.input.readAddress(".susds"),
            usds  : domain.input.readAddress(".usds")
        });

        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(mainnetInst.almProxy)))
        });

        ForeignControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new ForeignControllerInit.LayerZeroRecipient[](0);

        ForeignControllerInit.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients,
            layerZeroRecipients,
            true
        );

        vm.stopBroadcast();

        // Step 4: Export all relevant addresses

        ScriptTools.exportContract(domain.output, "freezer",    domain.input.readAddress(".freezer"));
        ScriptTools.exportContract(domain.output, "relayer",    domain.input.readAddress(".relayer"));
        ScriptTools.exportContract(domain.output, "almProxy",   controllerInst.almProxy);
        ScriptTools.exportContract(domain.output, "controller", controllerInst.controller);
        ScriptTools.exportContract(domain.output, "rateLimits", controllerInst.rateLimits);
    }

    function _setUpMainnetMintRecipients() internal {
        vm.selectFork(mainnet.forkId);
        vm.startBroadcast();

        MainnetController controller = MainnetController(mainnetInst.controller);

        controller.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            bytes32(uint256(uint160(baseInst.almProxy)))
        );
        controller.setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            bytes32(uint256(uint160(arbitrumInst.almProxy)))
        );

        vm.stopBroadcast();
    }

    /**********************************************************************************************/
    /*** Rate limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _setMainnetControllerRateLimits() internal {
        MainnetController controller = MainnetController(mainnetInst.controller);

        IRateLimits rateLimits = IRateLimits(mainnetInst.rateLimits);

        _onboardAAVEToken(mainnet, mainnetInst, AUSDC,  maxAmount6,  slope6);
        _onboardAAVEToken(mainnet, mainnetInst, AUSDS,  maxAmount18, slope18);
        _onboardAAVEToken(mainnet, mainnetInst, SPUSDC, maxAmount6,  slope6);

        _onboardERC4626Token(mainnet, mainnetInst, address(controller.susde()), maxAmount18, slope18);
        _onboardERC4626Token(mainnet, mainnetInst, Ethereum.SUSDS,              maxAmount18, slope18);
        _onboardERC4626Token(mainnet, mainnetInst, FLUID_SUSDS_VAULT,           maxAmount18, slope18);

        vm.startBroadcast();

        bytes32 susdeDepositKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(), address(controller.susde()));

        bytes32 syrupUsdcDepositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(), SYRUP_USDC);
        bytes32 syrupUsdcWithdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_MAPLE_REDEEM(), SYRUP_USDC);

        bytes32 domainKeyArbitrum = RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        bytes32 domainKeyBase     = RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);

        // USDS mint/burn and cross-chain transfer rate limits
        rateLimits.setRateLimitData(domainKeyBase,                   maxAmount6,  slope6);
        rateLimits.setRateLimitData(domainKeyArbitrum,               maxAmount6,  slope6);
        rateLimits.setRateLimitData(controller.LIMIT_USDS_MINT(),    maxAmount18, slope18);
        rateLimits.setRateLimitData(controller.LIMIT_USDS_TO_USDC(), maxAmount6,  slope6);

        rateLimits.setUnlimitedRateLimitData(controller.LIMIT_USDC_TO_CCTP());

        // Ethena-specific rate limits
        rateLimits.setRateLimitData(controller.LIMIT_SUSDE_COOLDOWN(), maxAmount18, slope18);
        rateLimits.setRateLimitData(controller.LIMIT_USDE_BURN(),      maxAmount18, slope18);
        rateLimits.setRateLimitData(controller.LIMIT_USDE_MINT(),      maxAmount6,  slope6);
        rateLimits.setRateLimitData(susdeDepositKey,                   maxAmount18, slope18);

        // Maple-specific deposit/withdraw rate limits
        rateLimits.setRateLimitData(syrupUsdcDepositKey, maxAmount6, slope6);

        rateLimits.setUnlimitedRateLimitData(syrupUsdcWithdrawKey);

        vm.stopBroadcast();
    }

    function _setForeignControllerRateLimits(Domain memory domain, ControllerInstance memory controllerInst) internal {
        vm.selectFork(domain.forkId);
        vm.startBroadcast();

        ForeignController foreignController = ForeignController(controllerInst.controller);

        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        bytes32 psmDepositKey  = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey = foreignController.LIMIT_PSM_WITHDRAW();

        bytes32 domainKeyEthereum = RateLimitHelpers.makeUint32Key(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        usdc  = domain.input.readAddress(".usdc");
        usds  = domain.input.readAddress(".usds");
        susds = domain.input.readAddress(".susds");

        // PSM rate limits for all three assets
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  usdc),  maxAmount6,  slope6);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, usdc),  maxAmount6,  slope6);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  usds),  maxAmount18, slope18);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  susds), maxAmount18, slope18);
        
        rateLimits.setUnlimitedRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, usds));
        rateLimits.setUnlimitedRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, susds));

        // CCTP rate limits
        rateLimits.setRateLimitData(domainKeyEthereum, maxAmount6, slope6);
        rateLimits.setUnlimitedRateLimitData(foreignController.LIMIT_USDC_TO_CCTP());

        vm.stopBroadcast();
    }

    function _setArbitrumRateLimits() internal {
        _setForeignControllerRateLimits(arbitrum, arbitrumInst);
    }

    function _setBaseRateLimits() internal {
        _setForeignControllerRateLimits(base, baseInst);

        _onboardAAVEToken(base, baseInst, AUSDC_BASE, maxAmount6, slope6);

        _onboardERC4626Token(base, baseInst, FLUID_SUSDS_VAULT_BASE,  maxAmount6, slope6);
        _onboardERC4626Token(base, baseInst, Base.MORPHO_VAULT_SUSDC, maxAmount6, slope6);
    }

    /**********************************************************************************************/
    /*** Rate limit utility functions                                                           ***/
    /**********************************************************************************************/

    function _onboardAAVEToken(
        Domain memory             domain,
        ControllerInstance memory controllerInst,
        address                   aToken,
        uint256                   maxAmount,
        uint256                   slope
    )
        internal
    {
        vm.selectFork(domain.forkId);
        vm.startBroadcast();

        // NOTE: MainnetController and ForeignController both have the same LIMIT constants for this
        bytes32 depositKey  = MainnetController(controllerInst.controller).LIMIT_AAVE_DEPOSIT();
        bytes32 withdrawKey = MainnetController(controllerInst.controller).LIMIT_AAVE_WITHDRAW();

        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(depositKey,  aToken), maxAmount,         slope);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(withdrawKey, aToken), type(uint256).max, 0);

        vm.stopBroadcast();
    }

    function _onboardERC4626Token(
        Domain memory             domain,
        ControllerInstance memory controllerInst,
        address                   token,
        uint256                   maxAmount,
        uint256                   slope
    )
        internal
    {
        vm.selectFork(domain.forkId);
        vm.startBroadcast();

        // NOTE: MainnetController and ForeignController both have the same LIMIT constants for this
        bytes32 depositKey  = MainnetController(controllerInst.controller).LIMIT_4626_DEPOSIT();
        bytes32 withdrawKey = MainnetController(controllerInst.controller).LIMIT_4626_WITHDRAW();

        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(depositKey,  token), maxAmount,         slope);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(withdrawKey, token), type(uint256).max, 0);

        vm.stopBroadcast();
    }

    /**********************************************************************************************/
    /*** Script running functions                                                               ***/
    /**********************************************************************************************/

    function run() public {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        deployer = msg.sender;

        // Step 1: Declare domains and source files

        mainnet = Domain({
            input  : ScriptTools.loadConfig("mainnet-staging"),
            output : "mainnet-staging",
            forkId : vm.createFork(getChain("mainnet").rpcUrl),
            admin  : deployer
        });
        arbitrum = Domain({
            input  : ScriptTools.loadConfig("arbitrum_one-staging"),
            output : "arbitrum_one-staging",
            forkId : vm.createFork(getChain("arbitrum_one").rpcUrl),
            admin  : deployer
        });
        base = Domain({
            input  : ScriptTools.loadConfig("base-staging"),
            output : "base-staging",
            forkId : vm.createFork(getChain("base").rpcUrl),
            admin  : deployer
        });

        // Ballpark sizing of rate limits, tokens in PSMs, etc
        // Ballpark sizing of USDS to put in the join contracts, PSMs, etc
        USDC_UNIT_SIZE = mainnet.input.readUint(".usdcUnitSize") * 1e6;
        USDS_UNIT_SIZE = mainnet.input.readUint(".usdsUnitSize") * 1e18;

        maxAmount18 = USDC_UNIT_SIZE * 1e12 * 5;
        slope18     = USDC_UNIT_SIZE * 1e12 / 4 hours;
        maxAmount6  = USDC_UNIT_SIZE * 5;
        slope6      = USDC_UNIT_SIZE / 4 hours;

        // Step 2: Deploy and configure all mainnet contracts

        _setUpMainnetDependencies();
        _setUpMainnetAllocationSystem();
        _setUpMainnetController();
        _setMainnetControllerRateLimits();

        // Step 3: Deploy and configure all L2 contracts, and set them as mint recipients on mainnet

        arbitrumInst = _setUpForeignALMController(arbitrum);
        baseInst     = _setUpForeignALMController(base);

        _setUpMainnetMintRecipients();

        // Step 4: Set rate limits for all L2 contracts

        _setArbitrumRateLimits();
        _setBaseRateLimits();

        // Step 4: Export deployer address

        ScriptTools.exportContract(mainnet.output,  "admin", deployer);
        ScriptTools.exportContract(arbitrum.output, "admin", deployer);
        ScriptTools.exportContract(base.output,     "admin", deployer);
    }

}
