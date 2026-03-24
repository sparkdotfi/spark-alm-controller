// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ControllerBase }                             from "./ControllerBase.sol";
import { bytes4ToKeyComponent, combineKeyComponents } from "./ParameterKeys.sol";
import { ParameterHelpers }                           from "./ParameterHelpers.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";
import { IController }     from "./interfaces/IController.sol";
import { IParameters }     from "./interfaces/IParameters.sol";

contract Controller is IController, ControllerBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    string public constant FACET_PARAMETER_KEY_PREFIX = "sky.pau.controller.facet";

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(
        address accessControls_,
        address parameters_,
        address proxy_,
        address rateLimits_
    ) {
        ControllerStorage storage $ = _getControllerStorage();

        $.accessControls = accessControls_;
        $.parameters     = parameters_;
        $.proxy          = proxy_;
        $.rateLimits     = rateLimits_;
    }

    /**********************************************************************************************/
    /*** Diamond Functions                                                                      ***/
    /**********************************************************************************************/

    function setFacet(bytes4 callSelector, address facet, bytes4 delegateSelector) external {
        ControllerStorage storage $ = _getControllerStorage();

        require(
            IAccessControls($.accessControls).hasRole(_DEFAULT_ADMIN_ROLE, msg.sender),
            NotAdmin(msg.sender)
        );

        IParameters($.parameters).set(
            _getFacetKey(callSelector),
            ParameterHelpers.fromBytes24(bytes24(abi.encodePacked(facet, delegateSelector)))
        );

        emit FacetSet(callSelector, facet, delegateSelector);
    }

    fallback() external payable {
        ( address facet, bytes4 delegateSelector ) = _getFacet(msg.sig);

        require(facet != address(0), FacetNotFound(msg.sig));

        // Replace the incoming selector with the delegate selector.
        ( bool success, bytes memory returnData ) = facet.delegatecall(
            abi.encodePacked(delegateSelector, msg.data[4:])
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

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getFacetKey(bytes4 callSelector) internal pure returns (string memory key) {
        return combineKeyComponents(FACET_PARAMETER_KEY_PREFIX, bytes4ToKeyComponent(callSelector));
    }

    function _getFacet(bytes4 callSelector)
        internal
        view
        returns (address facet, bytes4 delegateSelector)
    {
        bytes24 data = ParameterHelpers.toBytes24(
            IParameters(_getControllerStorage().parameters).get(_getFacetKey(callSelector))
        );

        return ( address(bytes20(data)), bytes4(data << 160) );
    }

}
