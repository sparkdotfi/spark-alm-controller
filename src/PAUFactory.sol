// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    AccessControlEnumerable
} from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { IAccessControls } from "./interfaces/IAccessControls.sol";

import { AccessControls } from "./AccessControls.sol";
import { ALMProxy }       from "./ALMProxy.sol";
import { Controller }     from "./Controller.sol";
import { RateLimits }     from "./RateLimits.sol";

import { IPAUFactory } from "./interfaces/IPAUFactory.sol";

contract PAUFactory is IPAUFactory, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override FACET_VALIDATOR_ROLE = keccak256("FACET_VALIDATOR_ROLE");

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    mapping (address facet => bool valid) public override isValidFacet;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin, address facetValidator) {
        require(admin          != address(0), ZeroAdmin());
        require(facetValidator != address(0), ZeroFacetValidator());

        _grantRole(DEFAULT_ADMIN_ROLE,   admin);
        _grantRole(FACET_VALIDATOR_ROLE, facetValidator);
    }

    /**********************************************************************************************/
    /*** External Interactive Facet Validator Functions                                         ***/
    /**********************************************************************************************/

    function setValidFacet(address facet, bool valid)
        external
        override
        onlyRole(FACET_VALIDATOR_ROLE)
    {
        _setValidFacet(facet, valid);
    }

    function setValidFacets(address[] calldata facets, bool[] calldata valid)
        external
        override
        onlyRole(FACET_VALIDATOR_ROLE)
    {
        for (uint256 i = 0; i < facets.length; ++i) {
            _setValidFacet(facets[i], valid[i]);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IPAUFactory, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IPAUFactory).interfaceId || super.supportsInterface(interfaceId);
    }

    /**********************************************************************************************/
    /*** Deploy Function                                                                        ***/
    /**********************************************************************************************/

    function deploy(address admin) external override returns (address controller) {
        // Step 1: Deploy ALMProxy and RateLimits contracts with the factory as initial admin.

        ALMProxy   almProxy   = new ALMProxy(address(this));
        RateLimits rateLimits = new RateLimits(address(this));

        address accessControls = address(new AccessControls(admin));

        controller = address(new Controller({
            accessControls_ : accessControls,
            factory_        : address(this),
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits)
        }));

        // Step 2: Grant CONTROLLER role on ALMProxy and RateLimits to the Controller.

        almProxy.grantRole(almProxy.CONTROLLER(),     controller);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller);

        // Step 3: Grant _DEFAULT_ADMIN_ROLE on ALMProxy and RateLimits to the passed admin.

        almProxy.grantRole(DEFAULT_ADMIN_ROLE,   admin);
        rateLimits.grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Step 4: Revoke factory's own _DEFAULT_ADMIN_ROLE on ALMProxy and RateLimits.

        almProxy.revokeRole(DEFAULT_ADMIN_ROLE,   address(this));
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        emit PAUDeployed(
            admin,
            controller,
            accessControls,
            address(almProxy),
            address(rateLimits)
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _setValidFacet(address facet, bool valid) internal {
        require(facet != address(0),   ZeroFacet());
        require(facet.code.length > 0, EmptyFacet());

        emit ValidFacetSet(facet, isValidFacet[facet] = valid);
    }

}
