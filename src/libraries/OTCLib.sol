// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

}

library OTCLib {

    struct OTC {
        address buffer;
        uint256 rechargeRate18;
        uint256 sent18;
        uint256 sentTimestamp;
        uint256 claimed18;
    }

    event OTCBufferSet(address indexed exchange, address indexed buffer);

    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed assetClaimed,
        uint256         amountClaimed,
        uint256         amountClaimed18
    );

    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256         amountSent,
        uint256         amountSent18
    );

    event OTCRechargeRateSet(address indexed exchange, uint256 rate18);

    event OTCWhitelistedAssetSet(
        address indexed exchange,
        address indexed asset,
        bool            isWhitelisted
    );

    bytes32 public constant LIMIT_SWAP = keccak256("LIMIT_OTC_SWAP");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setBuffer(
        address                             exchange,
        address                             otcBuffer,
        mapping(address => OTC)     storage otcs,
        mapping(address => uint256) storage maxSlippages
    )
        external
    {
        require(exchange  != address(0), "OTCLib/exchange-zero-address");
        require(otcBuffer != address(0), "OTCLib/otcBuffer-zero-address");
        require(exchange  != otcBuffer,  "OTCLib/exchange-equals-otcBuffer");

        OTC storage otc = otcs[exchange];

        // Prevent rotating buffer while a swap is pending and not ready
        require(
            otc.sentTimestamp == 0 || isSwapReady(exchange, otcs, maxSlippages),
            "OTCLib/swap-in-progress"
        );

        emit OTCBufferSet(exchange, otc.buffer = otcBuffer);
    }

    function setRechargeRate(
        address                         exchange,
        uint256                         rechargeRate18,
        mapping(address => OTC) storage otcs
    )
        external
    {
        require(exchange != address(0), "OTCLib/exchange-zero-address");

        emit OTCRechargeRateSet(exchange, otcs[exchange].rechargeRate18 = rechargeRate18);
    }

    function setWhitelistedAsset(
        address                                              exchange,
        address                                              asset,
        bool                                                 isWhitelisted,
        mapping(address => mapping(address => bool)) storage whitelistedAssets,
        mapping(address => OTC)                      storage otcs
    )
        external
    {
        require(exchange              != address(0), "OTCLib/exchange-zero-address");
        require(asset                 != address(0), "OTCLib/asset-zero-address");
        require(otcs[exchange].buffer != address(0), "OTCLib/otc-buffer-not-set");

        whitelistedAssets[exchange][asset] = isWhitelisted;

        emit OTCWhitelistedAssetSet(exchange, asset, isWhitelisted);
    }

    function send(
        address                                              proxy,
        address                                              rateLimits,
        address                                              exchange,
        address                                              assetToSend,
        uint256                                              amount,
        mapping(address => mapping(address => bool)) storage whitelistedAssets,
        mapping(address => OTC)                      storage otcs,
        mapping(address => uint256)                  storage maxSlippages
    )
        external
    {
        require(assetToSend != address(0), "OTCLib/asset-to-send-zero");
        require(amount > 0,                "OTCLib/amount-to-send-zero");

        require(whitelistedAssets[exchange][assetToSend], "OTCLib/asset-not-whitelisted");

        // NOTE: This will lose precision for tokens with >18 decimals.
        uint256 sent18 = amount * 1e18 / 10 ** IERC20Like(assetToSend).decimals();

        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_SWAP, exchange),
            sent18
        );

        OTC storage otc = otcs[exchange];

        require(isSwapReady(exchange, otcs, maxSlippages), "OTCLib/last-swap-not-returned");

        otc.sent18        = sent18;
        otc.sentTimestamp = block.timestamp;
        otc.claimed18     = 0;

        _transfer(proxy, assetToSend, exchange, amount);

        emit OTCSwapSent(exchange, otcs[exchange].buffer, assetToSend, amount, sent18);
    }

    function claim(
        address                                              proxy,
        address                                              exchange,
        address                                              assetToClaim,
        mapping(address => mapping(address => bool)) storage whitelistedAssets,
        mapping(address => OTC)                      storage otcs
    )
        external
    {
        address otcBuffer = otcs[exchange].buffer;

        require(assetToClaim != address(0), "OTCLib/asset-to-claim-zero");
        require(otcBuffer    != address(0), "OTCLib/otc-buffer-not-set");

        require(whitelistedAssets[exchange][assetToClaim], "OTCLib/asset-not-whitelisted");

        uint256 amountToClaim   = IERC20Like(assetToClaim).balanceOf(otcBuffer);
        uint256 amountToClaim18 = amountToClaim * 1e18 / 10 ** IERC20Like(assetToClaim).decimals();

        otcs[exchange].claimed18 += amountToClaim18;

        _transferFrom(proxy, assetToClaim, otcBuffer, proxy, amountToClaim);

        emit OTCClaimed(exchange, otcBuffer, assetToClaim, amountToClaim, amountToClaim18);
    }

    function getClaimWithRecharge(
        address                         exchange,
        mapping(address => OTC) storage otcs
    )
        public
        view
        returns (uint256)
    {
        OTC memory otc = otcs[exchange];

        if (otc.sentTimestamp == 0) return 0;

        return otc.claimed18 + (block.timestamp - otc.sentTimestamp) * otc.rechargeRate18;
    }

    function isSwapReady(
        address                             exchange,
        mapping(address => OTC)     storage otcs,
        mapping(address => uint256) storage maxSlippages
    )
        public
        view
        returns (bool)
    {
        // If maxSlippages is not set, the exchange is not onboarded.
        if (maxSlippages[exchange] == 0) return false;

        return getClaimWithRecharge(exchange, otcs)
            >= otcs[exchange].sent18 * maxSlippages[exchange] / 1e18;
    }

    /**********************************************************************************************/
    /*** Internal functions                                                                     ***/
    /**********************************************************************************************/

    function _transfer(address proxy, address asset, address destination, uint256 amount) internal {
        bytes memory returnData = IALMProxy(proxy).doCall(
            asset,
            abi.encodeCall(IERC20Like.transfer, (destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "OTCLib/transfer-failed"
        );
    }

    function _transferFrom(
        address proxy,
        address asset,
        address source,
        address destination,
        uint256 amount
    )
        internal
    {
        bytes memory returnData = IALMProxy(proxy).doCall(
            asset,
            abi.encodeCall(IERC20Like.transferFrom, (source, destination, amount))
        );

        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "OTCLib/transferFrom-failed"
        );
    }

}
