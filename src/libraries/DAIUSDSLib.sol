// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }     from "../interfaces/IALMProxy.sol";
import { IDAIUSDSFacet } from "../interfaces/facets/IDAIUSDSFacet.sol";

import { FacetBase } from "./FacetBase.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IDAIUSDSLike {

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

contract DAIUSDSFacet is IDAIUSDSFacet, FacetBase {

    /**********************************************************************************************/
    /*** Immutable state                                                                       ***/
    /**********************************************************************************************/

    address public immutable dai;
    address public immutable daiUSDS;
    address public immutable usds;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address dai_, address daiUSDS_, address usds_) {
        dai     = dai_;
        daiUSDS = daiUSDS_;
        usds    = usds_;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(uint256 usdsAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getControllerStorage().proxy;

        ApproveLib.approve(usds, proxy, daiUSDS, usdsAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );
    }

    function swapDAIToUSDS(uint256 daiAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getControllerStorage().proxy;

        ApproveLib.approve(dai, proxy, daiUSDS, daiAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

}
