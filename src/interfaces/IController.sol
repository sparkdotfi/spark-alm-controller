// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IController {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Dispatch {
        address facet;
        bytes4  delegateSelector;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event DispatchSet(
        bytes4  indexed callSelector,
        address indexed facet,
        bytes4  indexed delegateSelector
    );

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the caller is not an admin.
    error NotAdmin(address caller);

    /// @notice Thrown when a dispatch is not found for a given call selector.
    error DispatchNotFound(bytes4 callSelector);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function setDispatch(bytes4 callSelector, address facet, bytes4 delegateSelector) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getDispatch(bytes4 callSelector)
        external
        view
        returns (address facet, bytes4 delegateSelector);

}
