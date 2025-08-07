// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Script.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ControllerInstance }                   from "../deploy/ControllerInstance.sol";
import { ForeignControllerInit as ForeignInit } from "../deploy/ForeignControllerInit.sol";
import { MainnetControllerInit as MainnetInit } from "../deploy/MainnetControllerInit.sol";

contract UpgradeMainnetController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        console.log("Upgrading mainnet controller...");

        string memory fileSlug = string(abi.encodePacked("mainnet-", vm.envString("ENV")));

        address newController = vm.envAddress("NEW_CONTROLLER");
        address oldController = vm.envAddress("OLD_CONTROLLER");

        vm.startBroadcast();

        string memory inputConfig = ScriptTools.readInput(fileSlug);

        ControllerInstance memory controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : newController,
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address[] memory relayers = new address[](2);
        relayers[0] = inputConfig.readAddress(".relayer");
        relayers[1] = inputConfig.readAddress(".backstopRelayer");

        MainnetInit.ConfigAddressParams memory configAddresses = MainnetInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayers      : relayers,
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

        MainnetInit.LayerZeroRecipient[] memory layerZeroRecipients = new MainnetInit.LayerZeroRecipient[](0);

        MainnetInit.CentrifugeRecipient[] memory centrifugeRecipients = new MainnetInit.CentrifugeRecipient[](0);

        string memory baseInputConfig = ScriptTools.readInput(string(abi.encodePacked("base-", vm.envString("ENV"))));

        address baseAlmProxy = baseInputConfig.readAddress(".almProxy");

        mintRecipients[0] = MainnetInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(baseAlmProxy)))
        });

        MainnetInit.upgradeController(controllerInst, configAddresses, checkAddresses, mintRecipients, layerZeroRecipients, centrifugeRecipients);

        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits upgraded at      ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", newController);
        console.log("Old Controller deprecated at", oldController);
    }

}

contract UpgradeForeignController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));

        address newController = vm.envAddress("NEW_CONTROLLER");
        address oldController = vm.envAddress("OLD_CONTROLLER");

        vm.createSelectFork(getChain(chainName).rpcUrl);

        console.log(string(abi.encodePacked("Upgrading ", chainName, " controller...")));

        vm.startBroadcast();

        string memory inputConfig = ScriptTools.readInput(fileSlug);

        ControllerInstance memory controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : newController,
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address[] memory relayers = new address[](2);
        relayers[0] = inputConfig.readAddress(".relayer");
        relayers[1] = inputConfig.readAddress(".backstopRelayer");

        ForeignInit.ConfigAddressParams memory configAddresses = ForeignInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayers      : relayers,
            oldController : oldController
        });

        ForeignInit.CheckAddressParams memory checkAddresses = ForeignInit.CheckAddressParams({
            admin : inputConfig.readAddress(".admin"),
            psm   : inputConfig.readAddress(".psm"),
            cctp  : inputConfig.readAddress(".cctpTokenMessenger"),
            usdc  : inputConfig.readAddress(".usdc")
            // susds : inputConfig.readAddress(".susds"),
            // usds  : inputConfig.readAddress(".usds")
        });

        string memory mainnetInputConfig = ScriptTools.readInput(string(abi.encodePacked("mainnet-", vm.envString("ENV"))));

        address mainnetAlmProxy = mainnetInputConfig.readAddress(".almProxy");

        ForeignInit.LayerZeroRecipient[] memory layerZeroRecipients = new ForeignInit.LayerZeroRecipient[](0);

        ForeignInit.MintRecipient[] memory mintRecipients = new ForeignInit.MintRecipient[](1);

        mintRecipients[0] = ForeignInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(mainnetAlmProxy)))
        });

        ForeignInit.CentrifugeRecipient[] memory centrifugeRecipients = new ForeignInit.CentrifugeRecipient[](1);

        centrifugeRecipients[0] = ForeignInit.CentrifugeRecipient({
            destinationCentrifugeId : 1, // Ethereum Mainnet Centrifuge ID
            recipient               : bytes32(uint256(uint160(mainnetAlmProxy)))
        });

        ForeignInit.upgradeController(controllerInst, configAddresses, checkAddresses, mintRecipients, layerZeroRecipients, centrifugeRecipients);

        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits upgraded at      ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", newController);
        console.log("Old controller deprecated at", oldController);
    }

}
