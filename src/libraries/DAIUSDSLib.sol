// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy } from "../interfaces/IALMProxy.sol";

import { ApproveLib } from "./ApproveLib.sol";

interface IDAIUSDSLike {

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

library DAIUSDSLib {

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swapUSDSToDAI(
        address proxy,
        address usds,
        address daiUSDS,
        uint256 usdsAmount
    )
        external
    {
        ApproveLib.approve(usds, proxy, daiUSDS, usdsAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );
    }

    function swapDAIToUSDS(
        address proxy,
        address dai,
        address daiUSDS,
        uint256 daiAmount
    )
        external
    {
        ApproveLib.approve(dai, proxy, daiUSDS, daiAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

}
