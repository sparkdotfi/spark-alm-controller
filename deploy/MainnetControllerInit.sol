// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { MainnetController } from "../src/MainnetController.sol";

import { IALMProxy }   from "../src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../src/interfaces/IRateLimits.sol";

import { ControllerInstance } from "./ControllerInstance.sol";

interface IBufferLike {
    function approve(address, address, uint256) external;
}

interface IPSMLike {
    function kiss(address) external;
}

interface IVaultLike {
    function buffer() external view returns (address);
    function rely(address) external;
}

library MainnetControllerInit {

    /**********************************************************************************************/
    /*** Structs and constants                                                                  ***/
    /**********************************************************************************************/

    struct CheckAddressParams {
        address admin;
        address proxy;
        address rateLimits;
        address vault;
        address psm;
        address daiUsds;
        address cctp;
    }

    struct ConfigAddressParams {
        address freezer;
        address relayer;
        address oldController;
    }

    struct MintRecipient {
        uint32  domain;
        bytes32 mintRecipient;
    }

    struct InitParams {
        ControllerInstance  controllerInst;
        ConfigAddressParams configAddresses;
        CheckAddressParams  checkAddresses;
        MintRecipient[]     mintRecipients;
    }

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    /**********************************************************************************************/
    /*** Internal library functions                                                             ***/
    /**********************************************************************************************/

    function initAlmSystem(
        address vault,
        address usds,
        ControllerInstance  memory controllerInst,
        ConfigAddressParams memory configAddresses,
        CheckAddressParams  memory checkAddresses,
        MintRecipient[]     memory mintRecipients
    )
        internal
    {
        // Step 1: Do sanity checks outside of the controller

        require(IALMProxy(controllerInst.almProxy).hasRole(DEFAULT_ADMIN_ROLE, checkAddresses.admin),     "MainnetControllerInit/incorrect-admin-almProxy");
        require(IRateLimits(controllerInst.rateLimits).hasRole(DEFAULT_ADMIN_ROLE, checkAddresses.admin), "MainnetControllerInit/incorrect-admin-rateLimits");

        // Step 2: Initialize the controller

        InitParams[] memory params = new InitParams[](1);
        params[0] = InitParams({
            controllerInst:  controllerInst,
            configAddresses: configAddresses,
            checkAddresses:  checkAddresses,
            mintRecipients:  mintRecipients
        });

        _initController(params);

        // Step 3: Configure almProxy within the allocation system

        require(vault == checkAddresses.vault, "MainnetControllerInit/incorrect-vault");

        IVaultLike(vault).rely(controllerInst.almProxy);
        IBufferLike(IVaultLike(vault).buffer()).approve(usds, controllerInst.almProxy, type(uint256).max);
    }

    function upgradeController(
        ControllerInstance  memory controllerInst,
        ConfigAddressParams memory configAddresses,
        CheckAddressParams  memory checkAddresses,
        MintRecipient[]     memory mintRecipients
    )
        internal
    {
        InitParams[] memory params = new InitParams[](1);
        params[0] = InitParams({
            controllerInst:  controllerInst,
            configAddresses: configAddresses,
            checkAddresses:  checkAddresses,
            mintRecipients:  mintRecipients
        });

        _initController(params);

        IALMProxy   almProxy   = IALMProxy(controllerInst.almProxy);
        IRateLimits rateLimits = IRateLimits(controllerInst.rateLimits);

        require(configAddresses.oldController != address(0), "MainnetControllerInit/old-controller-zero-address");

        require(almProxy.hasRole(almProxy.CONTROLLER(), configAddresses.oldController),     "MainnetControllerInit/old-controller-not-almProxy-controller");
        require(rateLimits.hasRole(rateLimits.CONTROLLER(), configAddresses.oldController), "MainnetControllerInit/old-controller-not-rateLimits-controller");

        almProxy.revokeRole(almProxy.CONTROLLER(), configAddresses.oldController);
        rateLimits.revokeRole(rateLimits.CONTROLLER(), configAddresses.oldController);
    }

    function pauseProxyInitAlmSystem(address psm, address almProxy) internal {
        IPSMLike(psm).kiss(almProxy);  // To allow using no fee functionality
    }

    /**********************************************************************************************/
    /*** Private helper functions                                                               ***/
    /**********************************************************************************************/

    function _initController(InitParams[] memory params) private {
        for (uint256 i = 0; i < params.length; i++) {

            // Step 1: Perform controller sanity checks

            MainnetController newController = MainnetController(params[i].controllerInst.controller);

            require(newController.hasRole(DEFAULT_ADMIN_ROLE, params[i].checkAddresses.admin), "MainnetControllerInit/incorrect-admin-controller");

            require(address(newController.proxy())      == params[i].controllerInst.almProxy,   "MainnetControllerInit/incorrect-almProxy");
            require(address(newController.rateLimits()) == params[i].controllerInst.rateLimits, "MainnetControllerInit/incorrect-rateLimits");

            require(address(newController.vault())   == params[i].checkAddresses.vault,   "MainnetControllerInit/incorrect-vault");
            require(address(newController.psm())     == params[i].checkAddresses.psm,     "MainnetControllerInit/incorrect-psm");
            require(address(newController.daiUsds()) == params[i].checkAddresses.daiUsds, "MainnetControllerInit/incorrect-daiUsds");
            require(address(newController.cctp())    == params[i].checkAddresses.cctp,    "MainnetControllerInit/incorrect-cctp");

            require(newController.psmTo18ConversionFactor() == 1e12, "MainnetControllerInit/incorrect-psmTo18ConversionFactor");

            require(params[i].configAddresses.oldController != address(newController), "MainnetControllerInit/old-controller-is-new-controller");

            // Step 2: Configure ACL permissions controller, almProxy, and rateLimits

            IALMProxy   almProxy   = IALMProxy(params[i].controllerInst.almProxy);
            IRateLimits rateLimits = IRateLimits(params[i].controllerInst.rateLimits);

            newController.grantRole(newController.FREEZER(), params[i].configAddresses.freezer);
            newController.grantRole(newController.RELAYER(), params[i].configAddresses.relayer);

            almProxy.grantRole(almProxy.CONTROLLER(), address(newController));
            rateLimits.grantRole(rateLimits.CONTROLLER(), address(newController));

            // Step 3: Configure the mint recipients on other domains

            for (uint256 j = 0; j < params[i].mintRecipients.length; j++) {
                newController.setMintRecipient(params[i].mintRecipients[j].domain, params[i].mintRecipients[j].mintRecipient);
            }
        }
    }

}
