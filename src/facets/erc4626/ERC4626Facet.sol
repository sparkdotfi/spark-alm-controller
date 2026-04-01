// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IERC4626Facet } from "./IERC4626Facet.sol";

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

contract ERC4626Facet is IERC4626Facet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.ERC4626Facet
    struct FacetStorage {
        mapping (address token => uint256 maxExchangeRate) maxExchangeRates;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.ERC4626Facet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x2d0a40172b84813d0e50253809f3803008e18680eae5581bd5ffdf3dfdf76f00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_DEPOSIT  = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 public constant override LIMIT_WITHDRAW = keccak256("LIMIT_4626_WITHDRAW");

    uint256 public constant override EXCHANGE_RATE_PRECISION = 1e36;

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

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

    function deposit(address token, uint256 amount, uint256 minSharesOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(LIMIT_DEPOSIT, token, amount);

        address proxy = _getSharedControllerStorage().proxy;

        // Approve asset to token from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(IERC4626Like(token).asset(), proxy, token, amount);

        // Deposit asset into the token, proxy receives token shares, decode the resulting shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.deposit, (amount, proxy))
            ),
            (uint256)
        );

        require(shares >= minSharesOut, "ERC4626Facet/min-shares-out-not-met");

        require(
            _getExchangeRate(shares, amount) <= _getFacetStorage().maxExchangeRates[token],
            "ERC4626Facet/exchange-rate-too-high"
        );
    }

    function withdraw(address token, uint256 amount, uint256 maxSharesIn)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(LIMIT_WITHDRAW, token, amount);

        address proxy = _getSharedControllerStorage().proxy;

        // Withdraw asset from a token, decode resulting shares.
        // Assumes proxy has adequate token shares.
        shares = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.withdraw, (amount, proxy, proxy))
            ),
            (uint256)
        );

        require(shares <= maxSharesIn, "ERC4626Facet/shares-burned-too-high");

        _increaseRateLimit(LIMIT_DEPOSIT, token, amount);
    }

    function redeem(address token, uint256 shares, uint256 minAssetsOut)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assets)
    {
        address proxy = _getSharedControllerStorage().proxy;

        // Redeem shares for assets from the token, decode the resulting assets.
        // Assumes proxy has adequate token shares.
        assets = abi.decode(
            IALMProxy(proxy).doCall(
                token,
                abi.encodeCall(IERC4626Like.redeem, (shares, proxy, proxy))
            ),
            (uint256)
        );

        require(assets >= minAssetsOut, "ERC4626Facet/min-assets-out-not-met");

        _decreaseRateLimit(LIMIT_WITHDRAW, token, assets);
        _increaseRateLimit(LIMIT_DEPOSIT,  token, assets);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getMaxExchangeRate(address token) external view override returns (uint256) {
        return _getFacetStorage().maxExchangeRates[token];
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, address token, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(key, token),
            amount
        );
    }

    function _increaseRateLimit(bytes32 key, address token, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitIncrease(
            makeAddressKey(key, token),
            amount
        );
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
