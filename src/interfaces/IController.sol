// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IController {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Circuit {
        address facet;
        Wire[]  wires;
    }

    struct Dispatch {
        address facet;
        bytes4  delegateSelector;
    }

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event WireAdded(
        bytes4  indexed callSelector,
        bytes4  indexed delegateSelector,
        address indexed facet
    );

    event WireRemoved(bytes4 indexed callSelector);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when a when a call selector is already wired to a facet.
    error CallSelectorAlreadyWired(bytes4 callSelector);

    /// @notice Thrown when the call selector is hardcoded.
    error CallSelectorHardcoded(bytes4 callSelector);

    /// @notice Thrown when a call selector is not wired to a facet.
    error CallSelectorNotWired(bytes4 callSelector);

    /// @notice Thrown when an argument array is empty.
    error EmptyArray();

    /// @notice Thrown when the facet is not registered as valid on the factory.
    error InvalidFacet(address facet);

    /// @notice Thrown when the caller is not an admin.
    error NotAdmin(address caller);

    /// @notice Thrown when the dispatch is invalid.
    error ZeroFacet();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function addWire(address facet, Wire calldata wire) external;

    function addWires(address facet, Wire[] calldata wires) external;

    function removeAllWiresFor(address facet) external;

    function removeWire(bytes4 callSelector) external;

    function removeWires(bytes4[] calldata callSelectors) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function accessControls() external view returns (address);

    function circuits() external view returns (Circuit[] memory);

    function factory() external view returns (address);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getDispatch(bytes4 callSelector) external view returns (Dispatch memory);

    function getDispatches(bytes4[] calldata callSelectors)
        external
        view
        returns (Dispatch[] memory);

    function getWiring(address facet) external view returns (Wire[] memory);

    function getWirings(address[] calldata facets) external view returns (Wire[][] memory);

}
