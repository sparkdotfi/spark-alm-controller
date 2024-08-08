// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { AllocatorInit, AllocatorIlkConfig } from "dss-allocator/deploy/AllocatorInit.sol";

import {
    AllocatorIlkInstance,
    AllocatorSharedInstance
} from "dss-allocator/deploy/AllocatorInstances.sol";

import { AllocatorDeploy } from "dss-allocator/deploy/AllocatorDeploy.sol";

import { NstDeploy }   from "nst/deploy/NstDeploy.sol";
import { NstInit }     from "nst/deploy/NstInit.sol";
import { NstInstance } from "nst/deploy/NstInstance.sol";

import { ALMProxy }           from "src/ALMProxy.sol";
import { EthereumController } from "src/EthereumController.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

contract ForkTestBase is DssTest {

    bytes32 constant ILK = "ILK-A";

    /**********************************************************************************************/
    /*** Mainnet addresses                                                                      ***/
    /**********************************************************************************************/

    address constant LOG         = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant SPARK_PROXY = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;
    address constant PSM         = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;  // Lite PSM

    DssInstance dss;  // Mainnet DSS

    address ILK_REGISTRY;
    address PAUSE_PROXY;
    address USDC;

    /**********************************************************************************************/
    /*** NST addresses to be deployed                                                           ***/
    /**********************************************************************************************/

    AllocatorSharedInstance sharedInst;
    AllocatorIlkInstance    ilkInst;
    NstInstance             nstInst;

    /**********************************************************************************************/
    /*** Allocation system deployments                                                          ***/
    /**********************************************************************************************/

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy           almProxy;
    EthereumController ethereumController;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 20484600);  // August 8, 2024

        dss          = MCD.loadFromChainlog(LOG);
        PAUSE_PROXY  = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        ILK_REGISTRY = ChainlogLike(LOG).getAddress("ILK_REGISTRY");
        USDC         = ChainlogLike(LOG).getAddress("USDC");

        // Step 1: Deploy NST and allocation system

        nstInst = NstDeploy.deploy(
            address(this),
            PAUSE_PROXY,
            ChainlogLike(LOG).getAddress("MCD_JOIN_DAI")
        );

        sharedInst = AllocatorDeploy.deployShared(address(this), PAUSE_PROXY);

        ilkInst = AllocatorDeploy.deployIlk({
            deployer : address(this),
            owner    : PAUSE_PROXY,
            roles    : sharedInst.roles,
            ilk      : ILK,
            nstJoin  : nstInst.nstJoin
        });

        // Step 2: Deploy ALM system

        almProxy = new ALMProxy(admin);

        ethereumController = new EthereumController(
            admin,
            address(almProxy),
            address(ilkInst.vault),
            address(ilkInst.buffer),
            address(snst),
            address(psm)
        );

        AllocatorIlkConfig memory ilkConfig = AllocatorIlkConfig({
            ilk :            ILK,
            duty :           1000000001243680656318820312,
            maxLine :        100_000_000 * RAD,
            gap :            10_000_000 * RAD,
            ttl :            1 days,
            allocatorProxy : SPARK_PROXY,
            ilkRegistry :    ILK_REGISTRY
        });

        vm.startPrank(PAUSE_PROXY);

        NstInit.init(dss, nstInst);
        AllocatorInit.initShared(dss, sharedInst);
        AllocatorInit.initIlk(dss, sharedInst, ilkInst, ilkConfig);

        vm.stopPrank();
    }

    function test_base() public {

    }

}
