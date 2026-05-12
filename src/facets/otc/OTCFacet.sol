// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { makeAddressAddressKey } from "../../libraries/RateLimitHelpers.sol";

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

    bytes32 internal constant _LIMIT_SEND  = keccak256("LIMIT_OTC_SEND");
    bytes32 internal constant _LIMIT_CLAIM = keccak256("LIMIT_OTC_CLAIM");

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

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IOTCFacet
    function send(address exchange, address asset, uint256 amount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(asset != address(0), "OTCFacet/asset-zero-address");
        require(amount > 0,          "OTCFacet/zero-amount");

        FacetStorage storage $ = _getFacetStorage();

        address buffer = $.parameters[exchange].buffer;

        require(buffer != address(0), "OTCFacet/buffer-not-set");

        _decreaseRateLimit(getSendRateLimitKey(exchange, asset), amount);

        require(getIsSwapReady(exchange), "OTCFacet/last-swap-not-returned");

        State storage state = $.states[exchange];

        // NOTE: This will lose precision for tokens with >18 decimals.
        state.normalizedSent    = _toNormalizedAmount(asset, amount);
        state.sentTimestamp     = block.timestamp;
        state.normalizedClaimed = 0;

        _transfer(asset, exchange, amount);

        emit OTCSent(exchange, buffer, asset, amount);
    }

    /// @inheritdoc IOTCFacet
    function claim(address exchange, address asset)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(asset != address(0), "OTCFacet/asset-zero-address");

        FacetStorage storage $          = _getFacetStorage();
        Parameters   storage parameters = $.parameters[exchange];

        address buffer = parameters.buffer;

        require(buffer != address(0), "OTCFacet/buffer-not-set");

        require(
            _rateLimitExists(getClaimRateLimitKey(exchange, asset)),
            "OTCFacet/invalid-action"
        );

        uint256 amount = IERC20Like(asset).balanceOf(buffer);

        $.states[exchange].normalizedClaimed += _toNormalizedAmount(asset, amount);

        _transferFrom(asset, buffer, amount);

        emit OTCClaimed(exchange, buffer, asset, amount);
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
    function getSendRateLimitKey(address exchange, address asset)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_SEND, asset, exchange);
    }

    /// @inheritdoc IOTCFacet
    function getClaimRateLimitKey(address exchange, address asset)
        public
        pure
        override
        returns (bytes32)
    {
        return makeAddressAddressKey(_LIMIT_CLAIM, asset, exchange);
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
