// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IMerklFacet } from "./IMerklFacet.sol";

interface IMerklDistributorLike {

    function toggleOperator(address user, address operator) external;

}

contract MerklFacet is IMerklFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_TOGGLE_OPERATOR = keccak256("LIMIT_MERKL_TOGGLE_OPERATOR");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IMerklFacet
    function toggleOperator(address distributor, address operator)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(
            _rateLimitExists(getToggleOperatorRateLimitKey(distributor, operator)),
            "MerklFacet/invalid-action"
        );

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            distributor,
            abi.encodeCall(IMerklDistributorLike.toggleOperator, (proxy, operator))
        );

        emit MerklToggleOperator(distributor, operator);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IMerklFacet
    function getToggleOperatorRateLimitKey(address distributor, address operator)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_TOGGLE_OPERATOR, operator, distributor);
    }

}
