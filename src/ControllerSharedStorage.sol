// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

abstract contract ControllerSharedStorage {

    /**********************************************************************************************/
    /*** Shared Controller Storage Domain                                                       ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.SharedController
    struct SharedControllerStorage {
        address accessControls;
        address proxy;
        address rateLimits;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.SharedController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SHARED_CONTROLLER_STORAGE_LOCATION =
        0x77adf60bdbfedf206f8b8310f3d364080b7f61dcc0e46caac13c29bb1eb5cc00;

    function _getSharedControllerStorage()
        internal
        pure
        returns (SharedControllerStorage storage $)
    {
        assembly {
            $.slot := SHARED_CONTROLLER_STORAGE_LOCATION
        }
    }

}
