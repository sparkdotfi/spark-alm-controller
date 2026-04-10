// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUFactory } from "./interfaces/IPAUFactory.sol";

import { AccessControls } from "./AccessControls.sol";
import { ALMProxy }       from "./ALMProxy.sol";
import { Controller }     from "./Controller.sol";
import { RateLimits }     from "./RateLimits.sol";

contract PAUFactory is IPAUFactory {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override beacon;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address beacon_) {
        require((beacon = beacon_) != address(0), ZeroBeacon());
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function deploy(address admin) external override returns (address controller) {
        // Step 1: Deploy ALMProxy and RateLimits contracts with the factory as initial admin.

        ALMProxy   almProxy   = new ALMProxy(address(this));
        RateLimits rateLimits = new RateLimits(address(this));

        address accessControls = address(new AccessControls(admin));

        controller = address(new Controller({
            accessControls_ : accessControls,
            beacon_         : beacon,
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits)
        }));

        // Step 2: Grant CONTROLLER role on ALMProxy and RateLimits to the Controller.

        almProxy.grantRole(almProxy.CONTROLLER(),     controller);
        rateLimits.grantRole(rateLimits.CONTROLLER(), controller);

        // Step 3: Grant _DEFAULT_ADMIN_ROLE on ALMProxy and RateLimits to the passed admin.

        almProxy.grantRole(_DEFAULT_ADMIN_ROLE,   admin);
        rateLimits.grantRole(_DEFAULT_ADMIN_ROLE, admin);

        // Step 4: Revoke factory's own _DEFAULT_ADMIN_ROLE on ALMProxy and RateLimits.

        almProxy.revokeRole(_DEFAULT_ADMIN_ROLE,   address(this));
        rateLimits.revokeRole(_DEFAULT_ADMIN_ROLE, address(this));

        emit PAUDeployed(
            admin,
            controller,
            accessControls,
            address(almProxy),
            address(rateLimits)
        );
    }

}
