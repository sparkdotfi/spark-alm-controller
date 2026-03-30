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
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable distributor;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address distributor_) {
        distributor = distributor_;
    }

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function toggleOperator(address operator) external nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            distributor,
            abi.encodeCall(IMerklDistributorLike.toggleOperator, (proxy, operator))
        );
    }

}
