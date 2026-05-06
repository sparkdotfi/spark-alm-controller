// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IWrapProxyETHFacet } from "./IWrapProxyETHFacet.sol";

contract WrapProxyETHFacet is IWrapProxyETHFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_WRAP = keccak256("LIMIT_WRAP_PROXY_ETH");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IWrapProxyETHFacet
    address public immutable override weth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_) {
        require(weth_ != address(0), "WrapProxyETHFacet/zero-weth");

        weth = weth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IWrapProxyETHFacet
    function wrapAll() external override nonReentrant onlyRole(ALLOCATOR_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        uint256 ethAmount = proxy.balance;

        if (ethAmount == 0) return;

        require(_rateLimitExists(wrapRateLimitKey()), "WrapProxyETHFacet/invalid-action");

        IALMProxy(proxy).doCallWithValue(weth, "", ethAmount);

        emit WrapProxyETHWrap(ethAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IWrapProxyETHFacet
    function wrapRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_WRAP;
    }

}
