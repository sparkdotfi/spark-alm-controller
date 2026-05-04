// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }                            from "../../libraries/ApproveLib.sol";
import { makeAddressAddressKey, makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IERC4626Facet } from "./IERC4626Facet.sol";

interface IERC20Like {

    function balanceOf(address owner) external view returns (uint256);

}

interface IERC4626Like {

    function deposit(uint256 amount, address receiver) external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    function asset() external view returns (address);

}

contract ERC4626Facet is IERC4626Facet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.ERC4626Facet.v1
    struct FacetStorage {
        mapping (address token => uint256 maxExchangeRate) maxExchangeRates;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.ERC4626Facet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xff00b7bf03054889656e52db9e9ee5ee36d0a6360e21036fb566f0cbe8c36900;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_4626_WITHDRAW");

    /// @inheritdoc IERC4626Facet
    uint256 public constant override EXCHANGE_RATE_PRECISION = 1e36;

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC4626Facet
    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(token != address(0), "ERC4626Facet/token-zero-address");

        uint256 exchangeRate = _getExchangeRate(shares, maxExpectedAssets);

        _getFacetStorage().maxExchangeRates[token] = exchangeRate;

        emit ERC4626MaxExchangeRateSet(token, exchangeRate);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC4626Facet
    function deposit(address token, uint256 amount, uint256 minSharesOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        address proxy = _getSharedControllerStorage().proxy;
        address asset = IERC4626Like(token).asset();

        _decreaseRateLimit(getDepositRateLimitKey(token, asset), amount);

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(asset, proxy, token, amount);

        uint256 startingShares = IERC20Like(token).balanceOf(proxy);

        // Deposit asset into the token, proxy receives token shares.
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC4626Like.deposit, (amount, proxy)));

        shares = IERC20Like(token).balanceOf(proxy) - startingShares;

        require(shares >= minSharesOut, "ERC4626Facet/min-shares-out-not-met");

        require(
            _getExchangeRate(shares, amount) <= _getFacetStorage().maxExchangeRates[token],
            "ERC4626Facet/exchange-rate-too-high"
        );

        emit ERC4626Deposit(token, amount, shares);
    }

    /// @inheritdoc IERC4626Facet
    function withdraw(address token, uint256 amount, uint256 maxSharesIn)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(getWithdrawRateLimitKey(token), amount);

        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingShares = IERC20Like(token).balanceOf(proxy);

        // Withdraw asset from a token, assuming the proxy has adequate token shares.
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC4626Like.withdraw, (amount, proxy, proxy))
        );

        shares = startingShares - IERC20Like(token).balanceOf(proxy);

        require(shares <= maxSharesIn, "ERC4626Facet/shares-burned-too-high");

        _increaseRateLimit(getDepositRateLimitKey(token, IERC4626Like(token).asset()), amount);

        emit ERC4626Withdraw(token, amount, shares);
    }

    /// @inheritdoc IERC4626Facet
    function redeem(address token, uint256 shares, uint256 minAssetsOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assets)
    {
        address proxy = _getSharedControllerStorage().proxy;
        address asset = IERC4626Like(token).asset();

        uint256 startingAssets = IERC20Like(asset).balanceOf(proxy);

        // Redeem shares for assets from the token, assuming the proxy has adequate token shares.
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC4626Like.redeem, (shares, proxy, proxy)));

        assets = IERC20Like(asset).balanceOf(proxy) - startingAssets;

        require(assets >= minAssetsOut, "ERC4626Facet/min-assets-out-not-met");

        _decreaseRateLimit(getWithdrawRateLimitKey(token),       assets);
        _increaseRateLimit(getDepositRateLimitKey(token, asset), assets);

        emit ERC4626Redeem(token, shares, assets);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC4626Facet
    function getMaxExchangeRate(address token) external view override returns (uint256) {
        return _getFacetStorage().maxExchangeRates[token];
    }

    /// @inheritdoc IERC4626Facet
    function getDepositRateLimitKey(address token, address asset)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_DEPOSIT, asset, token);
    }

    /// @inheritdoc IERC4626Facet
    function getWithdrawRateLimitKey(address token) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_WITHDRAW, token);
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _getExchangeRate(uint256 shares, uint256 assets) internal pure returns (uint256) {
        // Return 0 for zero assets first, to handle the valid case of 0 shares and 0 assets.
        if (assets == 0) return 0;

        // Zero shares with non-zero assets is invalid (infinite exchange rate).
        require(shares > 0, "ERC4626Facet/zero-shares");

        return (EXCHANGE_RATE_PRECISION * assets) / shares;
    }

}
