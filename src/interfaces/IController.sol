// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IController {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event FacetSet(
        bytes4  indexed callSelector,
        address indexed facet,
        bytes4  indexed delegateSelector
    );

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the caller is not an admin.
    error NotAdmin(address caller);

    /// @notice Thrown when a facet is not found for a given call selector.
    error FacetNotFound(bytes4 callSelector);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function setFacet(bytes4 callSelector, address facet, bytes4 delegateSelector) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function FACET_PARAMETER_KEY_PREFIX() external pure returns (string memory key);

}
