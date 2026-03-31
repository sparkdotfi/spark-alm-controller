// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IDiamondPAUFactory {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event DiamondPAUDeployed(
        address indexed admin,
        address indexed controller,
        address         accessControls,
        address         almProxy,
        address         rateLimits
    );

    /**********************************************************************************************/
    /*** Functions                                                                              ***/
    /**********************************************************************************************/

    function deploy(address admin) external returns (address controller);

}
