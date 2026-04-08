// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

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

contract AaveFacet is IAaveFacet, FacetBase {

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

    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_AAVE_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

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

    function deposit(address aToken, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        address proxy = _getSharedControllerStorage().proxy;

        _decreaseRateLimit(LIMIT_DEPOSIT, aToken, amount);

        uint256 maxSlippage = _getFacetStorage().maxSlippages[aToken];

        require(maxSlippage != 0, "AaveFacet/max-slippage-not-set");

        address underlying = IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS();
        address pool       = IATokenWithPoolLike(aToken).POOL();

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

    function withdraw(address aToken, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 amountWithdrawn)
    {
        address proxy = _getSharedControllerStorage().proxy;

        // Withdraw underlying from Aave pool, decode resulting amount withdrawn.
        // Assumes proxy has adequate aTokens.
        amountWithdrawn = abi.decode(
            IALMProxy(proxy).doCall(
                IATokenWithPoolLike(aToken).POOL(),
                abi.encodeCall(
                    IPoolLike.withdraw,
                    (IATokenWithPoolLike(aToken).UNDERLYING_ASSET_ADDRESS(), amount, proxy)
                )
            ),
            (uint256)
        );

        _decreaseRateLimit(LIMIT_WITHDRAW, aToken, amountWithdrawn);
        _increaseRateLimit(LIMIT_DEPOSIT,  aToken, amountWithdrawn);

        emit AaveWithdraw(aToken, amountWithdrawn);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getMaxSlippage(address aToken) external view override returns (uint256) {
        return _getFacetStorage().maxSlippages[aToken];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, address aToken, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(key, aToken),
            amount
        );
    }

    function _increaseRateLimit(bytes32 key, address aToken, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitIncrease(
            makeAddressKey(key, aToken),
            amount
        );
    }

}
