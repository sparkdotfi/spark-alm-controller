// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Script.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ControllerInstance }                   from "../deploy/ControllerInstance.sol";
import { ForeignControllerInit as ForeignInit } from "../deploy/ForeignControllerInit.sol";
import { MainnetControllerInit as MainnetInit } from "../deploy/MainnetControllerInit.sol";

import { ForeignController }              from "../src/ForeignController.sol";
import { MainnetController }              from "../src/MainnetController.sol";
import { RateLimitData, RateLimitHelpers } from "../src/RateLimitHelpers.sol";

contract UpgradeMainnetController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        console.log("Upgrading mainnet controller...");

        string memory fileSlug = string(abi.encodePacked("mainnet-", vm.envString("ENV")));

        address oldController = vm.envAddress("OLD_CONTROLLER");

        string memory inputConfig = ScriptTools.readInput(fileSlug);

        ControllerInstance memory controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : inputConfig.readAddress(".controller"),
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        MainnetInit.ConfigAddressParams memory configAddresses = MainnetInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayer       : inputConfig.readAddress(".relayer"),
            oldController : oldController
        });

        MainnetInit.CheckAddressParams memory checkAddresses = MainnetInit.CheckAddressParams({
            admin      : inputConfig.readAddress(".admin"),
            proxy      : inputConfig.readAddress(".almProxy"),
            rateLimits : inputConfig.readAddress(".rateLimits"),
            vault      : inputConfig.readAddress(".allocatorVault"),
            psm        : inputConfig.readAddress(".psm"),
            daiUsds    : inputConfig.readAddress(".daiUsds"),
            cctp       : inputConfig.readAddress(".cctpTokenMessenger")
        });

        MainnetInit.MintRecipient[] memory mintRecipients = new MainnetInit.MintRecipient[](1);

        string memory baseInputConfig = ScriptTools.readInput(string(abi.encodePacked("base-", vm.envString("ENV"))));

        address baseAlmProxy = baseInputConfig.readAddress(".almProxy");

        mintRecipients[0] = MainnetInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(baseAlmProxy)))
        });

        vm.startBroadcast();

        MainnetInit.upgradeController(controllerInst, configAddresses, checkAddresses, mintRecipients);

        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits updated at       ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", controllerInst.controller);
        console.log("Old Controller deprecated at", oldController);
    }

}
contract ForeignControllerScript is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function _setUp()
        internal returns (
            ControllerInstance              memory controllerInst,
            ForeignInit.ConfigAddressParams memory configAddresses,
            ForeignInit.CheckAddressParams  memory checkAddresses,
            ForeignInit.MintRecipient[]     memory mintRecipients,
            string memory                          inputConfig,
            address                                oldController
        )
    {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));

        oldController = vm.envOr("OLD_CONTROLLER", address(0));

        vm.createSelectFork(getChain(chainName).rpcUrl);

        inputConfig = ScriptTools.readInput(fileSlug);

        controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : inputConfig.readAddress(".controller"),
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        configAddresses = ForeignInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayer       : inputConfig.readAddress(".relayer"),
            oldController : oldController
        });

        checkAddresses = ForeignInit.CheckAddressParams({
            admin : inputConfig.readAddress(".admin"),
            psm   : inputConfig.readAddress(".psm"),
            cctp  : inputConfig.readAddress(".cctpTokenMessenger"),
            usdc  : inputConfig.readAddress(".usdc"),
            susds : inputConfig.readAddress(".susds"),
            usds  : inputConfig.readAddress(".usds")
        });

        mintRecipients = new ForeignInit.MintRecipient[](1);

        string memory mainnetInputConfig = ScriptTools.readInput(string(abi.encodePacked("mainnet-", vm.envString("ENV"))));

        address mainnetAlmProxy = mainnetInputConfig.readAddress(".almProxy");

        mintRecipients[0] = ForeignInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(mainnetAlmProxy)))
        });
    }

}

contract InitForeignController is ForeignControllerScript {

    using stdJson     for string;
    using ScriptTools for string;

    bytes32 private constant LIMIT_USDS_TO_USDC   = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 private constant LIMIT_USDC_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 private constant LIMIT_USDC_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 private constant LIMIT_PSM_DEPOSIT    = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 private constant LIMIT_PSM_WITHDRAW   = keccak256("LIMIT_PSM_WITHDRAW");

    function run() external {
        (
            ControllerInstance              memory controllerInst,
            ForeignInit.ConfigAddressParams memory configAddresses,
            ForeignInit.CheckAddressParams  memory checkAddresses,
            ForeignInit.MintRecipient[]     memory mintRecipients,
            string memory                          inputConfig,
        ) = _setUp();

        // vm.startBroadcast();

        // ForeignInit.initAlmSystem(controllerInst, configAddresses, checkAddresses, mintRecipients);

        // _setBasicRateLimits(controllerInst, inputConfig);

        // vm.stopBroadcast();

        // console.log("ALMProxy initialized at  ", controllerInst.almProxy);
        // console.log("RateLimits initialized at", controllerInst.rateLimits);
        // console.log("Controller initialized at", controllerInst.controller);

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        uint32 cctpDomainId = uint32(vm.envUint("CCTP_DOMAIN_ID"));

        string memory fileSlug     = string(abi.encodePacked("mainnet-", vm.envString("ENV")));
        string memory mainnetConfig = ScriptTools.readInput(fileSlug);

        MainnetController mainnetController = MainnetController(mainnetConfig.readAddress(".controller"));

        vm.startBroadcast();

        // mainnetController.setMintRecipient(
        //     cctpDomainId,
        //     bytes32(uint256(uint160(address(controllerInst.almProxy))))
        // );

        address mainnetRateLimits = mainnetConfig.readAddress(".rateLimits");
        uint256 USDC_UNIT_SIZE    = ScriptTools.readInput("mainnet-staging").readUint(".usdcUnitSize") * 1e6;

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, cctpDomainId),
            mainnetRateLimits,
            RateLimitData({
                maxAmount : USDC_UNIT_SIZE * 5,
                slope     : USDC_UNIT_SIZE / 4 hours
            }),
            "usdsToUsdcData",
            6
        );

        vm.stopBroadcast();

        console.log("Mint recipient %s set at domain       %s", controllerInst.almProxy, cctpDomainId);
        console.log("USDS to USDC rate limit set at domain %s", cctpDomainId);
    }

    function _setBasicRateLimits(ControllerInstance memory controllerInst, string memory config) internal {
        ForeignController foreignController = ForeignController(controllerInst.controller);

        address rateLimits = controllerInst.rateLimits;

        bytes32 psmDepositKey  = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey = foreignController.LIMIT_PSM_WITHDRAW();

        bytes32 domainKeyEthereum = RateLimitHelpers.makeDomainKey(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        address usdc  = config.readAddress(".usdc");
        address usds  = config.readAddress(".usds");
        address susds = config.readAddress(".susds");

        uint256 USDC_UNIT_SIZE = ScriptTools.readInput("mainnet-staging").readUint(".usdcUnitSize") * 1e6;
        uint256 USDS_UNIT_SIZE = ScriptTools.readInput("mainnet-staging").readUint(".usdsUnitSize") * 1e18;

        RateLimitData memory rateLimitData18 = RateLimitData({
            maxAmount : USDS_UNIT_SIZE * 5,
            slope     : USDS_UNIT_SIZE / 4 hours
        });
        RateLimitData memory rateLimitData6 = RateLimitData({
            maxAmount : USDC_UNIT_SIZE * 5,
            slope     : USDC_UNIT_SIZE / 4 hours
        });
        RateLimitData memory unlimitedRateLimit = RateLimitHelpers.unlimitedRateLimit();

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
    }

}

contract UpgradeForeignController is ForeignControllerScript {

    function run() external {
        (
            ControllerInstance              memory controllerInst,
            ForeignInit.ConfigAddressParams memory configAddresses,
            ForeignInit.CheckAddressParams  memory checkAddresses,
            ForeignInit.MintRecipient[]     memory mintRecipients,
            ,
            address                                oldController
        ) = _setUp();

        vm.startBroadcast();

        ForeignInit.upgradeController(controllerInst, configAddresses, checkAddresses, mintRecipients);

        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits updated at       ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", controllerInst.controller);
        console.log("Old Controller deprecated at", oldController);
    }

}
