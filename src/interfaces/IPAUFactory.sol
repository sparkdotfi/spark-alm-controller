// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IPAUFactory is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event PAUDeployed(
        address indexed admin,
        address indexed controller,
        address         accessControls,
        address         almProxy,
        address         rateLimits
    );

    event ValidFacetSet( address indexed facet, bool valid);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    error ZeroFacet();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function deploy(address admin) external returns (address controller);

    function setValidFacet(address facet, bool valid) external;

    function setValidFacets(address[] calldata facets, bool[] calldata valid) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function FACET_VALIDATOR_ROLE() external view returns (bytes32);

    function isValidFacet(address facet) external view returns (bool);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
