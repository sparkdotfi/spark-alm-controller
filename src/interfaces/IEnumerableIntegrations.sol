// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IEnumerableIntegrations
 * @notice Shared interface for enumerating integrations, configs, and dispatch routing used by
 *         both the Beacon and the Controller.
 */
interface IEnumerableIntegrations {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @dev   Configuration for an integration: the facet contract and its selector wires.
     * @param facet Address of the facet contract.
     * @param wires Array of selector mappings from call selectors to delegate selectors.
     */
    struct Config {
        address facet;
        Wire[]  wires;
    }

    /**
     * @dev   Resolved dispatch entry mapping a call selector to its target facet and delegate
     *        selector.
     * @param facet            Address of the facet contract to delegate to.
     * @param delegateSelector The 4-byte selector to use in the delegatecall.
     */
    struct Dispatch {
        address facet;
        bytes4  delegateSelector;
    }

    /**
     * @dev   Full integration record containing its identifier and configuration.
     * @param id     Unique identifier for the integration.
     * @param config The integration's facet and wiring configuration.
     */
    struct Integration {
        bytes32 id;
        Config  config;
    }

    /**
     * @dev   Selector wire mapping an external call selector to an internal delegate selector
     *        on the facet.
     * @param callSelector     The 4-byte selector used in external calls to the controller.
     * @param delegateSelector The 4-byte selector forwarded to the facet via delegatecall.
     */
    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an integration is registered or updated.
     * @param  id     Unique identifier for the integration.
     * @param  config The facet address and selector wires that were set.
     */
    event IntegrationSet(bytes32 indexed id, Config config);

    /**
     * @notice Emitted when an integration is removed.
     * @param  id Unique identifier of the removed integration.
     */
    event IntegrationRemoved(bytes32 indexed id);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when a call selector is already wired to a facet.
    error CallSelectorAlreadyWired(bytes4 callSelector);

    /// @notice Thrown when the facet has no code.
    error EmptyFacet();

    /// @notice Thrown when the integration is not found.
    error IntegrationNotFound(bytes32 id);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Returns all registered integrations with their configs.
    function integrations() external view returns (Integration[] memory);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the config for a single integration.
     * @param  integrationId Unique identifier of the integration.
     * @return config        The facet address and selector wires for the integration.
     */
    function getConfig(bytes32 integrationId) external view returns (Config memory config);

    /**
     * @notice Returns configs for multiple integrations in a single call.
     * @param  integrationIds Array of integration identifiers.
     * @return configs        Array of configs corresponding to the given identifiers.
     */
    function getConfigs(bytes32[] calldata integrationIds)
        external
        view
        returns (Config[] memory configs);

    /**
     * @notice Returns the dispatch entry for a call selector.
     * @param  callSelector The 4-byte external call selector.
     * @return dispatch     The facet address and delegate selector for the given call selector.
     */
    function getDispatch(bytes4 callSelector) external view returns (Dispatch memory dispatch);

    /**
     * @notice Returns dispatch entries for multiple call selectors in a single call.
     * @param  callSelectors Array of 4-byte external call selectors.
     * @return dispatches    Array of dispatch entries corresponding to the given selectors.
     */
    function getDispatches(bytes4[] calldata callSelectors)
        external
        view
        returns (Dispatch[] memory dispatches);

}
