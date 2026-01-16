// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Script.sol";

import { ControllerInstance } from "../deploy/ControllerInstance.sol";

import { ForeignControllerDeploy, MainnetControllerDeploy } from "../deploy/ControllerDeploy.sol";

contract DeployMainnetFull is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        console.log("Deploying Mainnet ALMProxy, Controller and RateLimits...");

        string memory fileSlug = string(abi.encodePacked("mainnet-", vm.envString("ENV")));

        vm.startBroadcast();

        string memory config = ScriptTools.loadConfig(fileSlug);

        address psm = keccak256(abi.encodePacked(vm.envString("ENV"))) == keccak256(abi.encodePacked("staging"))
            ? config.readAddress(".psmWrapper")
            : config.readAddress(".psm");

        ControllerInstance memory instance = MainnetControllerDeploy.deployFull({
            admin   : config.readAddress(".admin"),
            vault   : config.readAddress(".allocatorVault"),
            psm     : psm,
            daiUsds : config.readAddress(".daiUsds"),
            cctp    : config.readAddress(".cctpTokenMessenger")
        });

        vm.stopBroadcast();

        console.log("ALMProxy   deployed at", instance.almProxy);
        console.log("Controller deployed at", instance.controller);
        console.log("RateLimits deployed at", instance.rateLimits);

        ScriptTools.exportContract(fileSlug, "almProxy",   instance.almProxy);
        ScriptTools.exportContract(fileSlug, "controller", instance.controller);
        ScriptTools.exportContract(fileSlug, "rateLimits", instance.rateLimits);
    }

}

contract DeployMainnetController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        console.log("Deploying Mainnet Controller...");

        string memory fileSlug = string(abi.encodePacked("mainnet-", vm.envString("ENV")));

        vm.startBroadcast();

        string memory config = ScriptTools.loadConfig(fileSlug);

        address psm = keccak256(abi.encodePacked(vm.envString("ENV"))) == keccak256(abi.encodePacked("staging"))
            ? config.readAddress(".psmWrapper")
            : config.readAddress(".psm");

        address controller = MainnetControllerDeploy.deployController({
            admin      : config.readAddress(".admin"),
            almProxy   : config.readAddress(".almProxy"),
            rateLimits : config.readAddress(".rateLimits"),
            vault      : config.readAddress(".allocatorVault"),
            psm        : psm,
            daiUsds    : config.readAddress(".daiUsds"),
            cctp       : config.readAddress(".cctpTokenMessenger")
        });

        vm.stopBroadcast();

        console.log("Controller deployed at", controller);

        ScriptTools.exportContract(fileSlug, "controller", controller);
    }

}

contract DeployForeignFull is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));
        string memory config    = ScriptTools.loadConfig(fileSlug);

        vm.createSelectFork(getChain(chainName).rpcUrl);

        console.log(string(abi.encodePacked("Deploying ", chainName, " ALMProxy, Controller and RateLimits...")));

        vm.startBroadcast();

        ControllerInstance memory instance = ForeignControllerDeploy.deployFull({
            admin : config.readAddress(".admin"),
            psm   : config.readAddress(".psm"),
            usdc  : config.readAddress(".usdc"),
            cctp  : config.readAddress(".cctpTokenMessenger")
        });

        vm.stopBroadcast();

        console.log("ALMProxy   deployed at", instance.almProxy);
        console.log("Controller deployed at", instance.controller);
        console.log("RateLimits deployed at", instance.rateLimits);

        ScriptTools.exportContract(fileSlug, "almProxy",   instance.almProxy);
        ScriptTools.exportContract(fileSlug, "controller", instance.controller);
        ScriptTools.exportContract(fileSlug, "rateLimits", instance.rateLimits);
    }

}

contract DeployForeignController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        string memory chainName = vm.envString("CHAIN");
        string memory fileSlug  = string(abi.encodePacked(chainName, "-", vm.envString("ENV")));
        string memory config    = ScriptTools.loadConfig(fileSlug);

        vm.createSelectFork(getChain(chainName).rpcUrl);

        console.log(string(abi.encodePacked("Deploying ", chainName, " Controller...")));

        vm.startBroadcast();

        address controller = ForeignControllerDeploy.deployController({
            admin      : config.readAddress(".admin"),
            almProxy   : config.readAddress(".almProxy"),
            rateLimits : config.readAddress(".rateLimits"),
            psm        : config.readAddress(".psm"),
            usdc       : config.readAddress(".usdc"),
            cctp       : config.readAddress(".cctpTokenMessenger")
        });

        vm.stopBroadcast();

        console.log("Controller deployed at", controller);

        ScriptTools.exportContract(fileSlug, "controller", controller);
    }

}
