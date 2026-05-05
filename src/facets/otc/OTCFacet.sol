// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IOTCFacet } from "./IOTCFacet.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

}

contract OTCFacet is IOTCFacet, Facet {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.OTCFacet.v1
    struct FacetStorage {
        mapping (address exchange => Parameters params) parameters;
        mapping (address exchange => State      state)  states;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.OTCFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xa486b3c0ee96d4f5203aaa145fd67532540f370a0bbe205b245ddac706af4e00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_SWAP = keccak256("LIMIT_OTC_SWAP");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IOTCFacet
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

    /// @inheritdoc IOTCFacet
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
            $.states[exchange].sentTimestamp == 0 || getIsSwapReady(exchange),
            "OTCFacet/swap-in-progress"
        );

        emit OTCBufferSet(exchange, $.parameters[exchange].buffer = buffer);
    }

    /// @inheritdoc IOTCFacet
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

    /// @inheritdoc IOTCFacet
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
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IOTCFacet
    function send(address exchange, address assetToSend, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(assetToSend != address(0), "OTCFacet/asset-to-send-zero");
        require(amount > 0,                "OTCFacet/amount-to-send-zero");

        FacetStorage storage $          = _getFacetStorage();
        Parameters   storage parameters = $.parameters[exchange];

        // NOTE: The only way an asset can be whitelisted is if the buffer is set.
        require(parameters.assetWhitelisted[assetToSend], "OTCFacet/asset-not-whitelisted");

        // NOTE: This will lose precision for tokens with >18 decimals.
        uint256 normalizedSent = _toNormalizedAmount(assetToSend, amount);

        _decreaseRateLimit(getSwapRateLimitKey(exchange), normalizedSent);

        require(getIsSwapReady(exchange), "OTCFacet/last-swap-not-returned");

        State storage state = $.states[exchange];

        state.normalizedSent    = normalizedSent;
        state.sentTimestamp     = block.timestamp;
        state.normalizedClaimed = 0;

        _transfer(assetToSend, exchange, amount);

        emit OTCSwapSent(exchange, parameters.buffer, assetToSend, amount, normalizedSent);
    }

    /// @inheritdoc IOTCFacet
    function claim(address exchange, address assetToClaim)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
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

        _transferFrom(assetToClaim, buffer, amount);

        emit OTCClaimed(exchange, buffer, assetToClaim, amount, normalizedAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IOTCFacet
    function getBuffer(address exchange) external view override returns (address) {
        return _getFacetStorage().parameters[exchange].buffer;
    }

    /// @inheritdoc IOTCFacet
    function getMaxSlippage(address exchange) external view override returns (uint256) {
        return _getFacetStorage().parameters[exchange].maxSlippage;
    }

    /// @inheritdoc IOTCFacet
    function getRechargeRate(address exchange) external view override returns (uint256) {
        return _getFacetStorage().parameters[exchange].normalizedRate;
    }

    /// @inheritdoc IOTCFacet
    function getIsWhitelisted(address exchange, address asset)
        external
        view
        override
        returns (bool)
    {
        return _getFacetStorage().parameters[exchange].assetWhitelisted[asset];
    }

    /// @inheritdoc IOTCFacet
    function getState(address exchange)
        external
        view
        override
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed)
    {
        State storage state = _getFacetStorage().states[exchange];
        return (state.normalizedSent, state.sentTimestamp, state.normalizedClaimed);
    }

    /// @inheritdoc IOTCFacet
    function getClaimWithRecharge(address exchange) public view override returns (uint256) {
        FacetStorage storage $     = _getFacetStorage();
        State        storage state = $.states[exchange];

        if (state.sentTimestamp == 0) return 0;

        return
            state.normalizedClaimed +
            (block.timestamp - state.sentTimestamp) * $.parameters[exchange].normalizedRate;
    }

    /// @inheritdoc IOTCFacet
    function getIsSwapReady(address exchange) public view override returns (bool) {
        FacetStorage storage $ = _getFacetStorage();

        uint256 maxSlippage = $.parameters[exchange].maxSlippage;

        // If maxSlippage is not set, the exchange is not onboarded.
        if (maxSlippage == 0) return false;

        return
            getClaimWithRecharge(exchange) >=
            $.states[exchange].normalizedSent * maxSlippage / 1e18;
    }

    /// @inheritdoc IOTCFacet
    function getSwapRateLimitKey(address exchange) public pure override returns (bytes32) {
        return makeAddressKey(_LIMIT_SWAP, exchange);
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
