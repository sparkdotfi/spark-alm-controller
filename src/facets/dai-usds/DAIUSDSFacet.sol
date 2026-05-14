// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IDAIUSDSFacet } from "./IDAIUSDSFacet.sol";

interface IDAIUSDSLike {

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

contract DAIUSDSFacet is IDAIUSDSFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_USDS_TO_DAI = keccak256("LIMIT_DAIUSDS_SWAP_USDS_TO_DAI");
    bytes32 internal constant _LIMIT_DAI_TO_USDS = keccak256("LIMIT_DAIUSDS_SWAP_DAI_TO_USDS");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IDAIUSDSFacet
    address public immutable override dai;

    /// @inheritdoc IDAIUSDSFacet
    address public immutable override daiUSDS;

    /// @inheritdoc IDAIUSDSFacet
    address public immutable override usds;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address dai_, address daiUSDS_, address usds_) {
        require(dai_     != address(0), "DAIUSDSFacet/zero-dai");
        require(daiUSDS_ != address(0), "DAIUSDSFacet/zero-daiUSDS");
        require(usds_    != address(0), "DAIUSDSFacet/zero-usds");

        dai     = dai_;
        daiUSDS = daiUSDS_;
        usds    = usds_;
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IDAIUSDSFacet
    function swapUSDSToDAI(uint256 usdsAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(usdsToDAISwapRateLimitKey(), usdsAmount);

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(usds, proxy, daiUSDS, usdsAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );

        // Clear approvals
        ApproveLib.approve(usds, proxy, daiUSDS, 0);

        emit DAIUSDSSwapUSDSToDAI(usdsAmount);
    }

    /// @inheritdoc IDAIUSDSFacet
    function swapDAIToUSDS(uint256 daiAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(daiToUSDSSwapRateLimitKey(), daiAmount);

        address proxy = _getSharedControllerStorage().proxy;

        ApproveLib.approve(dai, proxy, daiUSDS, daiAmount);

        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );

        // Clear approvals
        ApproveLib.approve(dai, proxy, daiUSDS, 0);

        emit DAIUSDSSwapDAIToUSDS(daiAmount);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IDAIUSDSFacet
    function usdsToDAISwapRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_USDS_TO_DAI;
    }

    /// @inheritdoc IDAIUSDSFacet
    function daiToUSDSSwapRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_DAI_TO_USDS;
    }

}
