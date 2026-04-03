// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { EnumerableSet }   from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ControllerSharedStorage } from "./ControllerSharedStorage.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";
import { IController }     from "./interfaces/IController.sol";
import { IPAUFactory }     from "./interfaces/IPAUFactory.sol";

contract Controller is IController, ControllerSharedStorage, ReentrancyGuard {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**********************************************************************************************/
    /*** Controller Storage Domain                                                              ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.Controller
    struct ControllerStorage {
        address                  factory;
        EnumerableSet.AddressSet facets;
        mapping (bytes4  => Dispatch)                 dispatches;
        mapping (address => EnumerableSet.Bytes32Set) wiring;
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
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyAdmin() {
        _revertIfNotAdmin();
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address accessControls_, address proxy_, address rateLimits_, address factory_) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        $.accessControls = accessControls_;
        $.proxy          = proxy_;
        $.rateLimits     = rateLimits_;

        _getControllerStorage().factory = factory_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function addWire(address facet, Wire calldata wire) external override nonReentrant onlyAdmin {
        _validateFacet(facet);
        _addWire(facet, wire);
    }

    function addWires(address facet, Wire[] calldata wires)
        external
        override
        nonReentrant
        onlyAdmin
    {
        require(wires.length > 0, EmptyArray());

        _validateFacet(facet);

        for (uint256 i = 0; i < wires.length; ++i) {
            _addWire(facet, wires[i]);
        }
    }

    function removeWire(bytes4 callSelector) external override nonReentrant onlyAdmin {
        _removeWire(callSelector);
    }

    function removeWires(bytes4[] calldata callSelectors) external override nonReentrant onlyAdmin {
        require(callSelectors.length > 0, EmptyArray());

        for (uint256 i = 0; i < callSelectors.length; ++i) {
            _removeWire(callSelectors[i]);
        }
    }

    function removeAllWiresFor(address facet) external override nonReentrant onlyAdmin {
        EnumerableSet.Bytes32Set storage wiring = _getControllerStorage().wiring[facet];

        uint256 wiringCount = wiring.length();

        require(wiringCount > 0, EmptyArray());

        while (wiringCount > 0) {
            ( bytes4 callSelector, ) = _fromWiring(wiring.at(0));

            _removeWire(callSelector);

            --wiringCount;
        }
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function accessControls() external view override returns (address) {
        return _getSharedControllerStorage().accessControls;
    }

    function factory() external view override returns (address) {
        return _getControllerStorage().factory;
    }

    function proxy() external view override returns (address) {
        return _getSharedControllerStorage().proxy;
    }

    function rateLimits() external view override returns (address) {
        return _getSharedControllerStorage().rateLimits;
    }

    function circuits() external view override returns (Circuit[] memory circuits_) {
        ControllerStorage storage $ = _getControllerStorage();

        uint256 facetCount = $.facets.length();

        circuits_ = new Circuit[](facetCount);

        for (uint256 i = 0; i < facetCount; ++i) {
            address facet = $.facets.at(i);

            circuits_[i] = Circuit(facet, _toWires($.wiring[facet]));
        }
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

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

    function getWiring(address facet) external view override returns (Wire[] memory wiring) {
        return _toWires(_getControllerStorage().wiring[facet]);
    }

    function getWirings(address[] calldata facets)
        external
        view
        override
        returns (Wire[][] memory wirings)
    {
        wirings = new Wire[][](facets.length);

        ControllerStorage storage $ = _getControllerStorage();

        for (uint256 i = 0; i < facets.length; ++i) {
            wirings[i] = _toWires($.wiring[facets[i]]);
        }
    }

    /**********************************************************************************************/
    /*** Fallback Functions                                                                     ***/
    /**********************************************************************************************/

    fallback() external payable {
        Dispatch storage dispatch = _getControllerStorage().dispatches[msg.sig];

        address facet = dispatch.facet;

        require(facet != address(0), CallSelectorNotWired(msg.sig));

        // Replace the incoming selector with the delegate selector.
        ( bool success, bytes memory returnData ) = facet.delegatecall(
            abi.encodePacked(dispatch.delegateSelector, msg.data[4:])
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

    function _addWire(address facet, Wire memory wire) internal {
        bytes4 callSelector     = wire.callSelector;
        bytes4 delegateSelector = wire.delegateSelector;

        _revertIfCallSelectorIsHardcoded(callSelector);

        ControllerStorage storage $ = _getControllerStorage();

        require(
            $.dispatches[callSelector].facet == address(0),
            CallSelectorAlreadyWired(callSelector)
        );

        $.facets.add(facet);

        $.dispatches[callSelector] = Dispatch(facet, delegateSelector);

        $.wiring[facet].add(_toWiring(callSelector, delegateSelector));

        emit WireAdded(callSelector, delegateSelector, facet);
    }

    function _removeWire(bytes4 callSelector) internal {
        _revertIfCallSelectorIsHardcoded(callSelector);

        ControllerStorage storage $ = _getControllerStorage();

        Dispatch storage dispatch = $.dispatches[callSelector];

        address facet = dispatch.facet;

        require(dispatch.facet != address(0), CallSelectorNotWired(callSelector));

        EnumerableSet.Bytes32Set storage wiring = $.wiring[facet];

        wiring.remove(_toWiring(callSelector, dispatch.delegateSelector));

        delete $.dispatches[callSelector];

        if (wiring.length() == 0) {
            $.facets.remove(facet);
        }

        emit WireRemoved(callSelector);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _fromWiring(bytes32 wiring)
        internal
        pure
        returns (bytes4 callSelector, bytes4 delegateSelector)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        return (bytes4(wiring), bytes4(wiring << 32));
    }

    function _toWiring(bytes4 callSelector, bytes4 delegateSelector)
        internal
        pure
        returns (bytes32 wiring)
    {
        return bytes32(abi.encodePacked(callSelector, delegateSelector));
    }

    function _toWires(EnumerableSet.Bytes32Set storage wiring)
        internal
        view
        returns (Wire[] memory wires)
    {
        uint256 wiringCount = wiring.length();

        wires = new Wire[](wiringCount);

        for (uint256 i = 0; i < wiringCount; ++i) {
            ( bytes4 callSelector, bytes4 delegateSelector ) = _fromWiring(wiring.at(i));

            wires[i] = Wire(callSelector, delegateSelector);
        }
    }

    function _revertIfNotAdmin() internal view {
        require(
            IAccessControls(_getSharedControllerStorage().accessControls).hasRole(
                _DEFAULT_ADMIN_ROLE,
                msg.sender
            ),
            NotAdmin(msg.sender)
        );
    }

    function _revertIfCallSelectorIsHardcoded(bytes4 callSelector) internal pure {
        require(
            callSelector != IController.addWire.selector &&
            callSelector != IController.addWires.selector &&
            callSelector != IController.removeWire.selector &&
            callSelector != IController.removeWires.selector &&
            callSelector != IController.removeAllWiresFor.selector &&
            callSelector != IController.accessControls.selector &&
            callSelector != IController.factory.selector &&
            callSelector != IController.proxy.selector &&
            callSelector != IController.rateLimits.selector &&
            callSelector != IController.circuits.selector &&
            callSelector != IController.getDispatch.selector &&
            callSelector != IController.getDispatches.selector &&
            callSelector != IController.getWiring.selector &&
            callSelector != IController.getWirings.selector,
            CallSelectorHardcoded(callSelector)
        );
    }

    function _validateFacet(address facet) internal view {
        require(facet != address(0), ZeroFacet());

        require(
            IPAUFactory(_getControllerStorage().factory).isValidFacet(facet),
            InvalidFacet(facet)
        );
    }

}
