// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Script.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ControllerInstance }                   from "../deploy/ControllerInstance.sol";
import { ForeignControllerInit as ForeignInit } from "../deploy/ForeignControllerInit.sol";
import { MainnetControllerInit as MainnetInit } from "../deploy/MainnetControllerInit.sol";

import { MainnetController } from "../src/MainnetController.sol";

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
            address                                oldController
        )
    {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));

        oldController = vm.envOr("OLD_CONTROLLER", address(0));

        vm.createSelectFork(getChain(chainName).rpcUrl);

        console.log(string(abi.encodePacked("Upgrading ", chainName, " controller...")));

        string memory inputConfig = ScriptTools.readInput(fileSlug);

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

    function run() external {
        (
            ControllerInstance              memory controllerInst,
            ForeignInit.ConfigAddressParams memory configAddresses,
            ForeignInit.CheckAddressParams  memory checkAddresses,
            ForeignInit.MintRecipient[]     memory mintRecipients,
        ) = _setUp();

        vm.startBroadcast();

        ForeignInit.initAlmSystem(controllerInst, configAddresses, checkAddresses, mintRecipients);

        vm.stopBroadcast();

        console.log("ALMProxy initialized at  ", controllerInst.almProxy);
        console.log("RateLimits initialized at", controllerInst.rateLimits);
        console.log("Controller initialized at", controllerInst.controller);



        vm.createSelectFork(getChain("mainnet").rpcUrl);

        uint32 cctpDomainId = uint32(vm.envUint("CCTP_DOMAIN_ID"));

        string memory fileSlug    = string(abi.encodePacked("mainnet-", vm.envString("ENV")));
        string memory inputConfig = ScriptTools.readInput(fileSlug);

        MainnetController controller = MainnetController(inputConfig.readAddress(".controller"));

        vm.startBroadcast();

        controller.setMintRecipient(
            cctpDomainId,
            bytes32(uint256(uint160(address( controllerInst.almProxy))))
        );

        vm.stopBroadcast();

        console.log("Mint recipient %s set at domain %s", controllerInst.almProxy, cctpDomainId);
    }

}

contract UpgradeForeignController is ForeignControllerScript {

    function run() external {
        (
            ControllerInstance              memory controllerInst,
            ForeignInit.ConfigAddressParams memory configAddresses,
            ForeignInit.CheckAddressParams  memory checkAddresses,
            ForeignInit.MintRecipient[]     memory mintRecipients,
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
