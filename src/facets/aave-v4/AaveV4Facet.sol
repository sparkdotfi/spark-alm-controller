// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import {
    makeAddressUint256AddressUint16AddressKey,
    makeAddressUint256Key
} from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IAaveV4Facet } from "./IAaveV4Facet.sol";

interface IAaveV4SpokeLike {

    struct Reserve {
        address underlying;
        address hub;
        uint16  assetId;
        uint8   decimals;
        uint24  collateralRisk;
        uint8   flags;
        uint32  dynamicConfigKey;
    }

    function supply(uint256 reserveId, uint256 amount, address onBehalfOf)
        external returns (uint256 suppliedShares, uint256 suppliedAmount);

    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf)
        external returns (uint256 withdrawnShares, uint256 withdrawnAmount);

    function getReserve(uint256 reserveId) external view returns (Reserve memory);

    function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IAaveV4HubLike {

    function getAssetDeficitRay(uint256 assetId) external view returns (uint256);

}

contract AaveV4Facet is IAaveV4Facet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.AaveV4Facet.v1
    struct FacetStorage {
        // 1e18 precision, keyed per market so each asset on a spoke gets its own tolerance.
        mapping (address spoke => mapping (uint256 reserveId => uint256 maxSlippage)) maxSlippages;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.AaveV4Facet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xfaa4b673fef63a93f9acc6a7f61e1b14d1e71d39344cfddfb7b4e936fd166b00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_AAVE_V4_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_AAVE_V4_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveV4Facet
    function setMaxSlippage(address spoke, uint256 reserveId, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(spoke != address(0), "AaveV4Facet/spoke-zero-address");

        _getFacetStorage().maxSlippages[spoke][reserveId] = maxSlippage;

        emit AaveV4MaxSlippageSet(spoke, reserveId, maxSlippage);
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveV4Facet
    function deposit(address spoke, uint256 reserveId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[spoke][reserveId];

        require(maxSlippage != 0, "AaveV4Facet/max-slippage-not-set");

        address proxy = _getSharedControllerStorage().proxy;

        IAaveV4SpokeLike.Reserve memory reserve = IAaveV4SpokeLike(spoke).getReserve(reserveId);

        address underlying = reserve.underlying;

        // Block deposits when the Hub asset carries any deficit: supplying against unbacked debt
        // would buy into the pool at par.
        require(
            IAaveV4HubLike(reserve.hub).getAssetDeficitRay(reserve.assetId) == 0,
            "AaveV4Facet/asset-deficit"
        );

        _decreaseRateLimit(
            getDepositRateLimitKey(spoke, reserveId, reserve.hub, reserve.assetId, underlying),
            amount
        );

        // Approve underlying to the spoke from the proxy (assumes the proxy has enough underlying).
        ApproveLib.approve(underlying, proxy, spoke, amount);

        uint256 startingBalance = IAaveV4SpokeLike(spoke).getUserSuppliedAssets(reserveId, proxy);

        // Supply underlying to the spoke, increasing the proxy's supplied position.
        IALMProxy(proxy).doCall(
            spoke,
            abi.encodeCall(IAaveV4SpokeLike.supply, (reserveId, amount, proxy))
        );

        // Measure the position change rather than trusting the returned (shares, amount) tuple.
        uint256 amountReceived
            = IAaveV4SpokeLike(spoke).getUserSuppliedAssets(reserveId, proxy) - startingBalance;

        require(amountReceived >= amount * maxSlippage / 1e18, "AaveV4Facet/slippage-too-high");

        // Clear the approval in case the spoke did not pull the full amount.
        ApproveLib.approve(underlying, proxy, spoke, 0);

        emit AaveV4Deposit(spoke, reserveId, amount);
    }

    /// @inheritdoc IAaveV4Facet
    function withdraw(address spoke, uint256 reserveId, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 amountWithdrawn)
    {
        address proxy = _getSharedControllerStorage().proxy;

        IAaveV4SpokeLike.Reserve memory reserve = IAaveV4SpokeLike(spoke).getReserve(reserveId);

        address underlying = reserve.underlying;

        uint256 startingBalance = IERC20Like(underlying).balanceOf(proxy);

        // Withdraw underlying from the spoke to the proxy.
        // An amount greater than the max withdrawable signals a full withdrawal.
        IALMProxy(proxy).doCall(
            spoke,
            abi.encodeCall(IAaveV4SpokeLike.withdraw, (reserveId, amount, proxy))
        );

        // Measure the amount actually received rather than trusting the return value.
        amountWithdrawn = IERC20Like(underlying).balanceOf(proxy) - startingBalance;

        _decreaseRateLimit(getWithdrawRateLimitKey(spoke, reserveId), amountWithdrawn);

        // The withdraw key omits the reserve-derived values, so a remapped reserve can still be
        // exited; only the restore below is skipped, since it resolves to an unconfigured key.
        _tryIncreaseRateLimit(
            getDepositRateLimitKey(spoke, reserveId, reserve.hub, reserve.assetId, underlying),
            amountWithdrawn
        );

        emit AaveV4Withdraw(spoke, reserveId, amountWithdrawn);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveV4Facet
    function getMaxSlippage(address spoke, uint256 reserveId)
        external
        view
        override
        returns (uint256)
    {
        return _getFacetStorage().maxSlippages[spoke][reserveId];
    }

    /// @inheritdoc IAaveV4Facet
    function getDepositRateLimitKey(
        address spoke,
        uint256 reserveId,
        address hub,
        uint16  assetId,
        address underlying
    )
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressUint256AddressUint16AddressKey(
            _LIMIT_DEPOSIT,
            spoke,
            reserveId,
            hub,
            assetId,
            underlying
        );
    }

    /// @inheritdoc IAaveV4Facet
    function getWithdrawRateLimitKey(address spoke, uint256 reserveId)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressUint256Key(_LIMIT_WITHDRAW, spoke, reserveId);
    }

}
