// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ControllerSharedStorage } from "./ControllerSharedStorage.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";
import { IController }     from "./interfaces/IController.sol";

contract Controller is IController, ControllerSharedStorage, ReentrancyGuard {

    /**********************************************************************************************/
    /*** Controller Storage Domain                                                              ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.Controller
    struct ControllerStorage {
        mapping(bytes4 => Dispatch) dispatches;
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
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address accessControls_, address proxy_, address rateLimits_) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        $.accessControls = accessControls_;
        $.proxy          = proxy_;
        $.rateLimits     = rateLimits_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function setDispatch(bytes4 callSelector, address facet, bytes4 delegateSelector)
        external
        nonReentrant
    {
        require(
            IAccessControls(_getSharedControllerStorage().accessControls).hasRole(
                _DEFAULT_ADMIN_ROLE,
                msg.sender
            ),
            NotAdmin(msg.sender)
        );

        _getControllerStorage().dispatches[callSelector] = Dispatch(facet, delegateSelector);

        emit DispatchSet(callSelector, facet, delegateSelector);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function accessControls() external view returns (address) {
        return _getSharedControllerStorage().accessControls;
    }

    function proxy() external view returns (address) {
        return _getSharedControllerStorage().proxy;
    }

    function rateLimits() external view returns (address) {
        return _getSharedControllerStorage().rateLimits;
    }

    function getDispatch(bytes4 callSelector)
        external
        view
        returns (address facet, bytes4 delegateSelector)
    {
        Dispatch storage dispatch = _getControllerStorage().dispatches[callSelector];

        return (dispatch.facet, dispatch.delegateSelector);
    }

    /**********************************************************************************************/
    /*** Fallback Functions                                                                     ***/
    /**********************************************************************************************/

    fallback() external payable {
        Dispatch storage dispatch = _getControllerStorage().dispatches[msg.sig];

        address facet = dispatch.facet;

        require(facet != address(0), DispatchNotFound(msg.sig));

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

    receive() external payable {}

}
