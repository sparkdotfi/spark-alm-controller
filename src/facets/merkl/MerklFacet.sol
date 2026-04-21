// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { FacetBase } from "../FacetBase.sol";

import { IMerklFacet } from "./IMerklFacet.sol";

interface IMerklDistributorLike {

    function toggleOperator(address user, address operator) external;

}

contract MerklFacet is IMerklFacet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.MerklFacet.v1
    struct FacetStorage {
        address distributor;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.MerklFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x35ec550679e4120f0ff38c33b01638a5da13a3f81e15282112300ac36c445d00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setDistributor(address distributor_)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(distributor_ != address(0), "MerklFacet/zero-distributor");

        emit MerklDistributorSet(_getFacetStorage().distributor = distributor_);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function toggleOperator(address operator)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        require(operator != address(0), "MerklFacet/zero-operator");

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            _getFacetStorage().distributor,
            abi.encodeCall(IMerklDistributorLike.toggleOperator, (proxy, operator))
        );

        emit MerklToggleOperator(operator);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IMerklFacet
    function distributor() external view override returns (address) {
        return _getFacetStorage().distributor;
    }

}
