// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {
    EnumerableSet
} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IBeacon }                 from "./interfaces/IBeacon.sol";
import { IController }             from "./interfaces/IController.sol";
import { IEnumerableIntegrations } from "./interfaces/IEnumerableIntegrations.sol";

contract Beacon is IBeacon, ReentrancyGuard, AccessControlEnumerable {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    // Enumerable index of configured integrations (mappings are not enumerable).
    EnumerableSet.Bytes32Set internal _integrationIds;

    // Canonical configuration per integration id.
    mapping (bytes32 integrationId => Config config) internal _configs;

    // Hot-path selector lookup used to ensure no override of a call selector.
    mapping (bytes4 callSelector => Dispatch dispatch) internal _dispatches;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        require(admin != address(0), ZeroAdmin());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setIntegration(bytes32 id, Config calldata config)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(config.facet != address(0),   ZeroFacet());
        require(config.facet.code.length > 0, EmptyFacet());
        require(config.wires.length > 0,      EmptyArray());

        if (!_integrationIds.add(id)) {
            // Remove the existing config and dispatches for this integration.
            _deleteConfigAndDispatches(id);
        }

        _setConfigAndDispatches(id, config);

        emit IntegrationSet(id, config);
    }

    function removeIntegration(bytes32 id)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_integrationIds.remove(id), IntegrationNotFound(id));

        // Remove the existing config and dispatches for this integration.
        _deleteConfigAndDispatches(id);

        emit IntegrationRemoved(id);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function integrations() external view override returns (Integration[] memory integrations_) {
        uint256 integrationCount = _integrationIds.length();

        integrations_ = new Integration[](integrationCount);

        for (uint256 i = 0; i < integrationCount; ++i) {
            bytes32 id = _integrationIds.at(i);

            integrations_[i] = Integration(id, _configs[id]);
        }
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getConfig(bytes32 integrationId) external view override returns (Config memory) {
        return _configs[integrationId];
    }

    function getConfigs(bytes32[] calldata integrationIds)
        external
        view
        override
        returns (Config[] memory integrationsConfig_)
    {
        integrationsConfig_ = new Config[](integrationIds.length);

        for (uint256 i = 0; i < integrationIds.length; ++i) {
            integrationsConfig_[i] = _configs[integrationIds[i]];
        }
    }

    function getDispatch(bytes4 callSelector)
        external
        view
        override
        returns (Dispatch memory dispatch)
    {
        return _dispatches[callSelector];
    }

    function getDispatches(bytes4[] calldata callSelectors)
        external
        view
        override
        returns (Dispatch[] memory dispatches)
    {
        dispatches = new Dispatch[](callSelectors.length);

        for (uint256 i = 0; i < callSelectors.length; ++i) {
            dispatches[i] = _dispatches[callSelectors[i]];
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IBeacon, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IBeacon).interfaceId || super.supportsInterface(interfaceId);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _deleteConfigAndDispatches(bytes32 integrationId) internal {
        Wire[] storage wires = _configs[integrationId].wires;

        for (uint256 i = wires.length; i > 0;) {
            delete _dispatches[wires[--i].callSelector];
            wires.pop();
        }

        delete _configs[integrationId];
    }

    function _setConfigAndDispatches(bytes32 id, Config calldata config) internal {
        Config storage storedConfig = _configs[id];

        storedConfig.facet = config.facet;

        Wire[] calldata wires = config.wires;

        for (uint256 i = 0; i < wires.length; ++i) {
            bytes4 callSelector     = wires[i].callSelector;
            bytes4 delegateSelector = wires[i].delegateSelector;

            _revertIfCallSelectorIsHardcoded(callSelector);

            require(
                _dispatches[callSelector].facet == address(0),
                CallSelectorAlreadyWired(callSelector)
            );

            storedConfig.wires.push(wires[i]);

            _dispatches[callSelector] = Dispatch(config.facet, delegateSelector);
        }
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfCallSelectorIsHardcoded(bytes4 callSelector) internal pure {
        require(
            callSelector != IEnumerableIntegrations.integrations.selector &&
            callSelector != IEnumerableIntegrations.getConfig.selector &&
            callSelector != IEnumerableIntegrations.getConfigs.selector &&
            callSelector != IEnumerableIntegrations.getDispatch.selector &&
            callSelector != IEnumerableIntegrations.getDispatches.selector &&
            callSelector != IController.updateIntegrations.selector &&
            callSelector != IController.removeIntegrations.selector &&
            callSelector != IController.accessControls.selector &&
            callSelector != IController.beacon.selector &&
            callSelector != IController.proxy.selector &&
            callSelector != IController.rateLimits.selector,
            CallSelectorHardcoded(callSelector)
        );
    }

}
