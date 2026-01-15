// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.21;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { AaveLib }      from "../src/libraries/AaveLib.sol";
import { ApproveLib }   from "../src/libraries/ApproveLib.sol";
import { CCTPLib }      from "../src/libraries/CCTPLib.sol";
import { CurveLib }     from "../src/libraries/CurveLib.sol";
import { ERC4626Lib }   from "../src/libraries/ERC4626Lib.sol";
import { PSMLib }       from "../src/libraries/PSMLib.sol";
import { UniswapV4Lib } from "../src/libraries/UniswapV4Lib.sol";

import "forge-std/Script.sol";

contract DeployLibs is Script {

    function _deploy(bytes memory creationCode) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(deployed != address(0), "DeployLibs/deploy-failed");
    }

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.startBroadcast();

        ScriptTools.exportContract("libraries", "AaveLib",      _deploy(type(AaveLib).creationCode));
        ScriptTools.exportContract("libraries", "ApproveLib",   _deploy(type(ApproveLib).creationCode));
        ScriptTools.exportContract("libraries", "CCTPLib",      _deploy(type(CCTPLib).creationCode));
        ScriptTools.exportContract("libraries", "CurveLib",     _deploy(type(CurveLib).creationCode));
        ScriptTools.exportContract("libraries", "ERC4626Lib",   _deploy(type(ERC4626Lib).creationCode));
        ScriptTools.exportContract("libraries", "PSMLib",       _deploy(type(PSMLib).creationCode));
        ScriptTools.exportContract("libraries", "UniswapV4Lib", _deploy(type(UniswapV4Lib).creationCode));

        vm.stopBroadcast();
    }

}