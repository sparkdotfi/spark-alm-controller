// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IBasinFacet } from "./IBasinFacet.sol";

interface IBasinLike {

    function deposit(address asset, address receiver, uint256 assetsToDeposit)
        external
        returns (uint256 newShares);

    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external
        returns (uint256 assetsWithdrawn);

    function shares(address user) external view returns (uint256);

}

contract BasinFacet is IBasinFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_BASIN_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_BASIN_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IBasinFacet
    function deposit(address basin, address asset, uint256 amount, uint256 minSharesOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(getDepositRateLimitKey(basin, asset), amount);

        address proxy = _getSharedControllerStorage().proxy;

        // Approve `asset` to Basin from the proxy (assumes the proxy has enough `asset`).
        ApproveLib.approve(asset, proxy, basin, amount);

        // Deposit `amount` of `asset` in the Basin, decode the result to get `shares`.
        // NOTE: The basin contract is immutable, so the return value can be trusted.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                basin,
                abi.encodeCall(IBasinLike.deposit, (asset, proxy, amount))
            ),
            (uint256)
        );

        require(shares >= minSharesOut, "BasinFacet/min-shares-out-not-met");

        emit BasinDeposit(basin, asset, amount, shares);
    }

    /// @inheritdoc IBasinFacet
    function withdraw(address basin, address asset, uint256 maxAmount, uint256 minConversionRate)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assetsWithdrawn)
    {
        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingShares = IBasinLike(basin).shares(proxy);

        // Withdraw up to `maxAmount` of `asset` in the Basin, decode the result to get
        // `assetsWithdrawn` (assumes the proxy has enough Basin shares).
        assetsWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                basin,
                abi.encodeCall(IBasinLike.withdraw, (asset, proxy, maxAmount))
            ),
            (uint256)
        );

        uint256 sharesBurned = startingShares - IBasinLike(basin).shares(proxy);

        require(
            assetsWithdrawn * 1e18 >= sharesBurned * minConversionRate,
            "BasinFacet/min-conversion-rate-not-met"
        );

        _decreaseRateLimit(getWithdrawRateLimitKey(basin, asset), assetsWithdrawn);

        emit BasinWithdraw(basin, asset, assetsWithdrawn, sharesBurned);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IBasinFacet
    function getDepositRateLimitKey(address basin, address asset)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_DEPOSIT, asset, basin);
    }

    /// @inheritdoc IBasinFacet
    function getWithdrawRateLimitKey(address basin, address asset)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_WITHDRAW, asset, basin);
    }

}
