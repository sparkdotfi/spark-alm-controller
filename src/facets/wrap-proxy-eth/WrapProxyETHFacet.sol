// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { FacetBase } from "../FacetBase.sol";

import { IWrapProxyETHFacet } from "./IWrapProxyETHFacet.sol";

contract WrapProxyETHFacet is IWrapProxyETHFacet, FacetBase {

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable weth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_) {
        weth = weth_;
    }

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function wrapAll() external nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy        = _getSharedControllerStorage().proxy;
        uint256 proxyBalance = proxy.balance;

        if (proxyBalance == 0) return;

        IALMProxy(proxy).doCallWithValue(weth, "", proxyBalance);
    }

}
