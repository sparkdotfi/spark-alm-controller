// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuardUpgradeable } from "../lib/oz-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {
    EnumerableSet
} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";
import { IBeacon }         from "./interfaces/IBeacon.sol";
import { IController }     from "./interfaces/IController.sol";

import { ControllerSharedStorage } from "./ControllerSharedStorage.sol";

contract Controller is IController, ControllerSharedStorage, ReentrancyGuardUpgradeable {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**********************************************************************************************/
    /*** Controller Storage Domain                                                              ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.Controller
    struct ControllerStorage {
        EnumerableSet.Bytes32Set integrationIds;
        mapping (bytes32 integrationId => Config config)     configs;
        mapping (bytes4  callSelector  => Dispatch dispatch) dispatches;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.Controller")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant CONTROLLER_STORAGE_LOCATION =
        0xee25394e09bdf9f095ffaf6289395c59de06e33ff54692b0774d5012253c4d00;

    function _getControllerStorage() internal pure returns (ControllerStorage storage $) {
        assembly {
            $.slot := CONTROLLER_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override beacon;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyAdmin() {
        _revertIfNotAdmin();
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address accessControls_, address beacon_, address proxy_, address rateLimits_)
        initializer
    {
        require(accessControls_ != address(0), ZeroAccessControls());
        require(beacon_         != address(0), ZeroBeacon());
        require(proxy_          != address(0), ZeroProxy());
        require(rateLimits_     != address(0), ZeroRateLimits());

        __ReentrancyGuard_init();

        SharedControllerStorage storage $ = _getSharedControllerStorage();

        $.accessControls = accessControls_;
        $.proxy          = proxy_;
        $.rateLimits     = rateLimits_;

        beacon = beacon_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function updateIntegrations(bytes32[] calldata ids) external override nonReentrant onlyAdmin {
        require(ids.length > 0, EmptyArray());

        Config[] memory configs = IBeacon(beacon).getConfigs(ids);

        ControllerStorage storage $ = _getControllerStorage();

        // Iterate over all integrationIds and set/overwrite each integration config
        for (uint256 i = 0; i < ids.length; ++i) {
            bytes32 id = ids[i];

            Config memory config = configs[i];

            require(config.facet != address(0),   IntegrationNotFound(id));
            require(config.facet.code.length > 0, EmptyFacet());
            require(config.wires.length > 0,      EmptyArray());

            if (!$.integrationIds.add(id)) {
                // Remove the existing config and dispatches for this integration.
                _deleteConfigAndDispatches(id);
            }

            _setConfigAndDispatches(id, config);

            emit IntegrationSet(id, config);
        }
    }

    function removeIntegrations(bytes32[] calldata ids) external override nonReentrant onlyAdmin {
        require(ids.length > 0, EmptyArray());

        ControllerStorage storage $ = _getControllerStorage();

        for (uint256 i = 0; i < ids.length; ++i) {
            bytes32 id = ids[i];

            require($.integrationIds.remove(id), IntegrationNotFound(id));

            _deleteConfigAndDispatches(id);

            emit IntegrationRemoved(id);
        }
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function accessControls() external view override returns (address) {
        return _getSharedControllerStorage().accessControls;
    }

    function integrations() external view override returns (Integration[] memory integrations_) {
        ControllerStorage storage $ = _getControllerStorage();

        uint256 integrationCount = $.integrationIds.length();

        integrations_ = new Integration[](integrationCount);

        for (uint256 i = 0; i < integrationCount; ++i) {
            bytes32 id = $.integrationIds.at(i);

            integrations_[i] = Integration(id, $.configs[id]);
        }
    }

    function proxy() external view override returns (address) {
        return _getSharedControllerStorage().proxy;
    }

    function rateLimits() external view override returns (address) {
        return _getSharedControllerStorage().rateLimits;
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getConfig(bytes32 integrationId) external view override returns (Config memory) {
        return _getControllerStorage().configs[integrationId];
    }

    function getConfigs(bytes32[] calldata integrationIds)
        external
        view
        override
        returns (Config[] memory integrationsConfig_)
    {
        integrationsConfig_ = new Config[](integrationIds.length);

        ControllerStorage storage $ = _getControllerStorage();

        for (uint256 i = 0; i < integrationIds.length; ++i) {
            integrationsConfig_[i] = $.configs[integrationIds[i]];
        }
    }

    function getDispatch(bytes4 callSelector)
        external
        view
        override
        returns (Dispatch memory dispatch)
    {
        return _getControllerStorage().dispatches[callSelector];
    }

    function getDispatches(bytes4[] calldata callSelectors)
        external
        view
        override
        returns (Dispatch[] memory dispatches)
    {
        dispatches = new Dispatch[](callSelectors.length);

        ControllerStorage storage $ = _getControllerStorage();

        for (uint256 i = 0; i < callSelectors.length; ++i) {
            dispatches[i] = $.dispatches[callSelectors[i]];
        }
    }

    /**********************************************************************************************/
    /*** Fallback Functions                                                                     ***/
    /**********************************************************************************************/

    fallback() external payable {
        require(msg.data.length >= 4, InvalidCallDataLength(msg.data.length));

        Dispatch storage dispatch = _getControllerStorage().dispatches[msg.sig];

        address facet = dispatch.facet;

        require(facet != address(0), CallSelectorNotWired(msg.sig));

        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address accessControls_ = $.accessControls;
        address proxy_          = $.proxy;
        address rateLimits_     = $.rateLimits;

        // Replace the incoming selector with the delegate selector.
        ( bool success, bytes memory returnData ) = facet.delegatecall(
            abi.encodePacked(dispatch.delegateSelector, msg.data[4:])
        );

        require(
            $.accessControls == accessControls_ && $.proxy == proxy_ && $.rateLimits == rateLimits_,
            SharedStorageAltered()
        );

        // Forward return data as-is (not possible without assembly in a fallback).
        // slither-disable-next-line assembly
        assembly {
            switch success
            case 0  { revert(add(returnData, 0x20), mload(returnData)) }
            default { return(add(returnData, 0x20), mload(returnData)) }
        }
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _deleteConfigAndDispatches(bytes32 integrationId) internal {
        ControllerStorage storage $     = _getControllerStorage();
        Wire[]            storage wires = $.configs[integrationId].wires;

        for (uint256 i = wires.length; i > 0;) {
            delete $.dispatches[wires[--i].callSelector];
            wires.pop();
        }

        delete $.configs[integrationId];
    }

    function _setConfigAndDispatches(bytes32 id, Config memory config) internal {
        ControllerStorage storage $            = _getControllerStorage();
        Config            storage storedConfig = $.configs[id];

        storedConfig.facet = config.facet;

        Wire[] memory wires = config.wires;

        for (uint256 i = 0; i < wires.length; ++i) {
            bytes4 callSelector     = wires[i].callSelector;
            bytes4 delegateSelector = wires[i].delegateSelector;

            require(
                $.dispatches[callSelector].facet == address(0),
                CallSelectorAlreadyWired(callSelector)
            );

            storedConfig.wires.push(wires[i]);

            $.dispatches[callSelector] = Dispatch(config.facet, delegateSelector);
        }
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        require(
            IAccessControls(_getSharedControllerStorage().accessControls).hasRole(
                _DEFAULT_ADMIN_ROLE,
                msg.sender
            ),
            NotAdmin(msg.sender)
        );
    }

}
