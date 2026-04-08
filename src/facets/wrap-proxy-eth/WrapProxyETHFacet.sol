// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { FacetBase } from "../FacetBase.sol";

import { IWrapProxyETHFacet } from "./IWrapProxyETHFacet.sol";

contract WrapProxyETHFacet is IWrapProxyETHFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override weth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_) {
        require(weth_ != address(0), "WrapProxyETHFacet/zero-weth");

        weth = weth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function wrapAll() external override nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        uint256 ethAmount = proxy.balance;

        if (ethAmount == 0) return;

        IALMProxy(proxy).doCallWithValue(weth, "", ethAmount);

        emit WrapProxyETHWrap(ethAmount);
    }

}
