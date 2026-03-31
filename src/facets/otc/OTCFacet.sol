// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IOTCFacet } from "./IOTCFacet.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

}

contract OTCFacet is IOTCFacet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.OTCFacet
    struct FacetStorage {
        mapping (address exchange => Parameters params) parameters;
        mapping (address exchange => State      state)  states;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.OTCFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x381032184f0875ab12ce62a17c374889bec43a2e17ec18539168704ac1f83200;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_SWAP = keccak256("LIMIT_OTC_SWAP");

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setMaxSlippage(address exchange, uint256 maxSlippage)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange != address(0), "OTCFacet/exchange-zero-address");
        require(maxSlippage > 0,        "OTCFacet/max-slippage-zero");

        _getFacetStorage().parameters[exchange].maxSlippage = maxSlippage;

        emit OTCMaxSlippageSet(exchange, maxSlippage);
    }

    function setBuffer(address exchange, address buffer)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange != address(0), "OTCFacet/exchange-zero-address");
        require(buffer   != address(0), "OTCFacet/otcBuffer-zero-address");
        require(exchange != buffer,     "OTCFacet/exchange-equals-otcBuffer");

        FacetStorage storage $ = _getFacetStorage();

        // Prevent rotating buffer while a swap is pending and not ready.
        require(
            $.states[exchange].sentTimestamp == 0 || isSwapReady(exchange),
            "OTCFacet/swap-in-progress"
        );

        emit OTCBufferSet(exchange, $.parameters[exchange].buffer = buffer);
    }

    function setRechargeRate(address exchange, uint256 normalizedRate)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange != address(0), "OTCFacet/exchange-zero-address");

        _getFacetStorage().parameters[exchange].normalizedRate = normalizedRate;

        emit OTCRechargeRateSet(exchange, normalizedRate);
    }

    function setIsWhitelisted(address exchange, address asset, bool isWhitelisted)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(exchange != address(0), "OTCFacet/exchange-zero-address");
        require(asset    != address(0), "OTCFacet/asset-zero-address");

        Parameters storage parameters = _getFacetStorage().parameters[exchange];

        require(parameters.buffer != address(0), "OTCFacet/buffer-not-set");

        parameters.assetWhitelisted[asset] = isWhitelisted;

        emit OTCWhitelistedAssetSet(exchange, asset, isWhitelisted);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function send(address exchange, address assetToSend, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        require(assetToSend != address(0), "OTCFacet/asset-to-send-zero");
        require(amount > 0,                "OTCFacet/amount-to-send-zero");

        FacetStorage storage $          = _getFacetStorage();
        Parameters   storage parameters = $.parameters[exchange];

        // NOTE: The only way an asset can be whitelisted is if the buffer is set.
        require(parameters.assetWhitelisted[assetToSend], "OTCFacet/asset-not-whitelisted");

        // NOTE: This will lose precision for tokens with >18 decimals.
        uint256 normalizedSent = _toNormalizedAmount(assetToSend, amount);

        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_SWAP, exchange),
            normalizedSent
        );

        require(isSwapReady(exchange), "OTCFacet/last-swap-not-returned");

        State storage state = $.states[exchange];

        state.normalizedSent    = normalizedSent;
        state.sentTimestamp     = block.timestamp;
        state.normalizedClaimed = 0;

        emit OTCSwapSent(exchange, parameters.buffer, assetToSend, amount, normalizedSent);

        _transfer(assetToSend, exchange, amount);
    }

    function claim(address exchange, address assetToClaim)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        require(assetToClaim != address(0), "OTCFacet/asset-to-claim-zero");

        FacetStorage storage $          = _getFacetStorage();
        Parameters   storage parameters = $.parameters[exchange];

        address buffer = parameters.buffer;

        require(buffer != address(0),                      "OTCFacet/buffer-not-set");
        require(parameters.assetWhitelisted[assetToClaim], "OTCFacet/asset-not-whitelisted");

        uint256 amount           = IERC20Like(assetToClaim).balanceOf(buffer);
        uint256 normalizedAmount = _toNormalizedAmount(assetToClaim, amount);

        $.states[exchange].normalizedClaimed += normalizedAmount;

        emit OTCClaimed(exchange, buffer, assetToClaim, amount, normalizedAmount);

        _transferFrom(assetToClaim, buffer, amount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getBuffer(address exchange) external view override returns (address) {
        return _getFacetStorage().parameters[exchange].buffer;
    }

    function getMaxSlippage(address exchange) external view override returns (uint256) {
        return _getFacetStorage().parameters[exchange].maxSlippage;
    }

    function getRechargeRate(address exchange) external view override returns (uint256) {
        return _getFacetStorage().parameters[exchange].normalizedRate;
    }

    function getIsWhitelisted(address exchange, address asset) external view override returns (bool) {
        return _getFacetStorage().parameters[exchange].assetWhitelisted[asset];
    }

    function getState(address exchange)
        external
        view
        override
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed)
    {
        State storage state = _getFacetStorage().states[exchange];
        return (state.normalizedSent, state.sentTimestamp, state.normalizedClaimed);
    }

    function getClaimWithRecharge(address exchange) public view override returns (uint256) {
        FacetStorage storage $     = _getFacetStorage();
        State        storage state = $.states[exchange];

        if (state.sentTimestamp == 0) return 0;

        return
            state.normalizedClaimed +
            (block.timestamp - state.sentTimestamp) * $.parameters[exchange].normalizedRate;
    }

    function isSwapReady(address exchange) public view override returns (bool) {
        FacetStorage storage $ = _getFacetStorage();

        uint256 maxSlippage = $.parameters[exchange].maxSlippage;

        // If maxSlippages is not set, the exchange is not onboarded.
        if (maxSlippage == 0) return false;

        return
            getClaimWithRecharge(exchange) >=
            $.states[exchange].normalizedSent * maxSlippage / 1e18;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _transfer(address asset, address destination, uint256 amount) internal {
        bytes memory returnData = IALMProxy(_getSharedControllerStorage().proxy).doCall(
            asset,
            abi.encodeCall(IERC20Like.transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "OTCFacet/transfer-failed"
        );
    }

    function _transferFrom(address asset, address source, uint256 amount) internal {
        address proxy = _getSharedControllerStorage().proxy;

        bytes memory returnData = IALMProxy(proxy).doCall(
            asset,
            abi.encodeCall(IERC20Like.transferFrom, (source, proxy, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "OTCFacet/transferFrom-failed"
        );
    }

    /**********************************************************************************************/
    /*** Internal View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function _toNormalizedAmount(address asset, uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / 10 ** IERC20Like(asset).decimals();
    }

}
