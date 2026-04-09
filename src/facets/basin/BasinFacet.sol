// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IBasinFacet } from "./IBasinFacet.sol";

interface IBasinLike {

    function deposit(address asset, address receiver, uint256 assetsToDeposit)
        external
        returns (uint256 newShares);

    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external
        returns (uint256 assetsWithdrawn);

}

contract BasinFacet is IBasinFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_BASIN_DEPOSIT");
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_BASIN_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    // NOTE: !!! This function was merged without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until Basin is live and
    //       all functionality has been thoroughly integration tested.
    function deposit(address basin, address asset, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(LIMIT_DEPOSIT, basin, asset, amount);

        address proxy = _getSharedControllerStorage().proxy;

        // Approve `asset` to Basin from the proxy (assumes the proxy has enough `asset`).
        ApproveLib.approve(asset, proxy, basin, amount);

        // Deposit `amount` of `asset` in the Basin, decode the result to get `shares`.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                basin,
                abi.encodeCall(IBasinLike.deposit, (asset, proxy, amount))
            ),
            (uint256)
        );

        emit BasinDeposit(basin, asset, amount, shares);
    }

    // NOTE: !!! This function was merged without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until Basin is live and
    //       all functionality has been thoroughly integration tested.
    function withdraw(address basin, address asset, uint256 maxAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assetsWithdrawn)
    {
        address proxy = _getSharedControllerStorage().proxy;

        // Withdraw up to `maxAmount` of `asset` in the Basin, decode the result to get
        // `assetsWithdrawn` (assumes the proxy has enough Basin shares).
        // NOTE: Rate limited at end of function, so cannot return here.
        assetsWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                basin,
                abi.encodeCall(IBasinLike.withdraw, (asset, proxy, maxAmount))
            ),
            (uint256)
        );

        _decreaseRateLimit(LIMIT_WITHDRAW, basin, asset, assetsWithdrawn);

        emit BasinWithdraw(basin, asset, assetsWithdrawn);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(
        bytes32 key,
        address basin,
        address asset,
        uint256 amount
    )
        internal
    {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressAddressKey(key, asset, basin),
            amount
        );
    }

}
