// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IAaveFacet } from "./IAaveFacet.sol";

interface IATokenWithPoolLike {

    function POOL() external view returns (address);

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IPoolLike {

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

}

contract AaveFacet is IAaveFacet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.AaveFacet.v1
    struct FacetStorage {
        mapping (address aToken => uint256 maxSlippage) maxSlippages;  // 1e18 precision
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.AaveFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x0d8c22a02210da5b8462182c9dc7f9ba6d9489bc70d480a9fc933c236c44b100;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveFacet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_AAVE_DEPOSIT");

    /// @inheritdoc IAaveFacet
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_AAVE_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveFacet
    function setMaxSlippage(address aToken, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(aToken != address(0), "AaveFacet/aToken-zero-address");

        emit AaveMaxSlippageSet(aToken, _getFacetStorage().maxSlippages[aToken] = maxSlippage);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveFacet
    function deposit(address aToken, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        uint256 maxSlippage = _getFacetStorage().maxSlippages[aToken];

        require(maxSlippage != 0, "AaveFacet/max-slippage-not-set");

        _decreaseRateLimit(_getDepositRateLimitKey(aToken), amount);

        address proxy      = _getSharedControllerStorage().proxy;
        address pool       = IATokenWithPoolLike(aToken).POOL();
        address underlying = IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS();

        // Approve underlying to Aave pool from the proxy (assumes the proxy has enough underlying).
        ApproveLib.approve(underlying, proxy, pool, amount);

        uint256 aTokenBalance = IERC20Like(aToken).balanceOf(proxy);

        // Deposit underlying into Aave pool, proxy receives aTokens.
        IALMProxy(proxy).doCall(
            pool,
            abi.encodeCall(IPoolLike.supply, (underlying, amount, proxy, 0))
        );

        uint256 newATokens = IERC20Like(aToken).balanceOf(proxy) - aTokenBalance;

        require(newATokens >= amount * maxSlippage / 1e18, "AaveFacet/slippage-too-high");

        emit AaveDeposit(aToken, amount);
    }

    /// @inheritdoc IAaveFacet
    function withdraw(address aToken, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 amountWithdrawn)
    {
        address proxy      = _getSharedControllerStorage().proxy;
        address underlying = IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS();

        uint256 startingBalance = IERC20Like(underlying).balanceOf(proxy);

        // Withdraw underlying from Aave pool, assuming the proxy has adequate aTokens.
        IALMProxy(proxy).doCall(
            IATokenWithPoolLike(aToken).POOL(),
            abi.encodeCall(IPoolLike.withdraw, (underlying, amount, proxy))
        );

        amountWithdrawn = IERC20Like(underlying).balanceOf(proxy) - startingBalance;

        _decreaseRateLimit(_getWithdrawRateLimitKey(aToken), amountWithdrawn);
        _increaseRateLimit(_getDepositRateLimitKey(aToken),  amountWithdrawn);

        emit AaveWithdraw(aToken, amountWithdrawn);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IAaveFacet
    function getMaxSlippage(address aToken) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[aToken];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

    function _increaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitIncrease(key, amount);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getDepositRateLimitKey(address aToken) internal view returns (bytes32) {
        return makeAddressAddressKey(
            LIMIT_DEPOSIT,
            IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS(),
            aToken
        );
    }

    function _getWithdrawRateLimitKey(address aToken) internal view returns (bytes32) {
        return makeAddressKey(LIMIT_WITHDRAW, aToken);
    }

}
