// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Script.sol";

import { ControllerInstance }                   from "../deploy/ControllerInstance.sol";
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
            daiUsds    : inputConfig.readAddress(".daiUsds")
        });

        MainnetInit.upgradeController(controllerInst, configAddresses, checkAddresses);

        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits upgraded at      ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", newController);
        console.log("Old Controller deprecated at", oldController);
    }

}
