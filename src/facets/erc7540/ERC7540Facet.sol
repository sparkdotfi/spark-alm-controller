// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IERC7540Facet } from "./IERC7540Facet.sol";

interface IERC4626Like {

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    function asset() external view returns (address);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function maxMint(address receiver) external view returns (uint256 maxShares);

    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

}

interface IERC7540Like {

    function requestDeposit(uint256 assets, address controller, address owner)
        external
        returns (uint256 requestId);

    function requestRedeem(uint256 shares, address controller, address owner)
        external
        returns (uint256 requestId);

}

contract ERC7540Facet is IERC7540Facet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC7540Facet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_7540_DEPOSIT");

    /// @inheritdoc IERC7540Facet
    bytes32 public constant override LIMIT_REDEEM = keccak256("LIMIT_7540_REDEEM");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC7540Facet
    function requestDeposit(address token, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        // Note that whitelist is done by rate limits.
        _decreaseRateLimit(LIMIT_DEPOSIT, token, amount);

        address proxy = _getSharedControllerStorage().proxy;

        // Approve asset to vault from the proxy (assumes the proxy has enough of the asset).
        ApproveLib.approve(IERC4626Like(token).asset(), proxy, token, amount);

        // Submit deposit request by transferring assets
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC7540Like.requestDeposit, (amount, proxy, proxy))
        );

        emit ERC7540RequestDeposit(token, amount);
    }

    /// @inheritdoc IERC7540Facet
    function claimDeposit(address token) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _rateLimitExists(makeAddressKey(LIMIT_DEPOSIT, token));

        address proxy  = _getSharedControllerStorage().proxy;
        uint256 shares = IERC4626Like(token).maxMint(proxy);

        // Claim shares from the vault to the proxy
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC4626Like.mint, (shares, proxy)));

        emit ERC7540ClaimDeposit(token, shares);
    }

    /// @inheritdoc IERC7540Facet
    function requestRedeem(address token, uint256 shares)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(LIMIT_REDEEM, token, IERC4626Like(token).convertToAssets(shares));

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC7540Like.requestRedeem, (shares, proxy, proxy))
        );

        emit ERC7540RequestRedeem(token, shares);
    }

    /// @inheritdoc IERC7540Facet
    function claimRedeem(address token) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _rateLimitExists(makeAddressKey(LIMIT_REDEEM, token));

        address proxy  = _getSharedControllerStorage().proxy;
        uint256 assets = IERC4626Like(token).maxWithdraw(proxy);

        // Claim assets from the vault to the proxy
        IALMProxy(proxy).doCall(
            token,
            abi.encodeCall(IERC4626Like.withdraw, (assets, proxy, proxy))
        );

        emit ERC7540ClaimRedeem(token, assets);
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

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _rateLimitExists(bytes32 key) internal view {
        require(
            IRateLimits(
                _getSharedControllerStorage().rateLimits
            ).getRateLimitData(key).maxAmount > 0,
            "ERC7540Facet/invalid-action"
        );
    }

}
