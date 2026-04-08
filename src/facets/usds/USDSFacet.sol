// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IUSDSFacet } from "./IUSDSFacet.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

}

interface IVaultLike {

    function buffer() external view returns (address);

    function draw(uint256 usdsAmount) external;

    function wipe(uint256 usdsAmount) external;

}

contract USDSFacet is IUSDSFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_MINT = keccak256("LIMIT_USDS_MINT");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override vault;
    address public immutable override usds;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address vault_, address usds_) {
        require(vault_ != address(0), "USDSFacet/zero-vault");
        require(usds_  != address(0), "USDSFacet/zero-usds");

        vault = vault_;
        usds  = usds_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function mint(uint256 usdsAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_MINT, usdsAmount);

        address proxy = $.proxy;

        // Mint USDS into the buffer.
        IALMProxy(proxy).doCall(vault, abi.encodeCall(IVaultLike.draw, (usdsAmount)));

        // Transfer USDS from the buffer to the proxy.
        // No need for ApproveLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(
                IERC20Like.transferFrom,
                (IVaultLike(vault).buffer(), proxy, usdsAmount)
            )
        );

        emit USDSMint(usdsAmount);
    }

    function burn(uint256 usdsAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitIncrease(LIMIT_MINT, usdsAmount);

        address proxy = $.proxy;

        // Transfer USDS from the proxy to the buffer.
        // No need for ApproveLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(IERC20Like.transfer, (IVaultLike(vault).buffer(), usdsAmount))
        );

        // Burn USDS from the buffer.
        IALMProxy(proxy).doCall(vault, abi.encodeCall(IVaultLike.wipe, (usdsAmount)));

        emit USDSBurn(usdsAmount);
    }

}
