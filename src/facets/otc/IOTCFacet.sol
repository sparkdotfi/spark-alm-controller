// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IOTCFacet
 * @notice PAU facet for over-the-counter (OTC) swaps via exchange/buffer pairs. The proxy sends
 *         assets to an exchange, and claims assets back from a buffer. A recharge rate tracks
 *         time-weighted claim eligibility to ensure the buffer returns value before the next swap.
 *         All normalized amounts use 18-decimal precision regardless of the token's native
 *         decimals.
 */
interface IOTCFacet is IFacet {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Parameters {
        address buffer;
        uint256 normalizedRate;
        uint256 maxSlippage;  // 1e18 precision
    }

    struct State {
        uint256 normalizedSent;
        uint256 sentTimestamp;
        uint256 normalizedClaimed;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a buffer address is configured for an exchange.
     * @param  exchange Address of the OTC exchange.
     * @param  buffer   Address of the buffer that returns swapped assets.
     */
    event OTCBufferSet(address indexed exchange, address indexed buffer);

    /**
     * @notice Emitted when assets are claimed from the buffer.
     * @param  exchange Address of the OTC exchange.
     * @param  buffer   Address of the buffer claimed from.
     * @param  asset    Address of the claimed asset token.
     * @param  amount   Amount claimed in native token decimals.
     */
    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed asset,
        uint256         amount
    );

    /**
     * @notice Emitted when the max slippage for an exchange is updated.
     * @param  exchange    Address of the OTC exchange.
     * @param  maxSlippage New max slippage in 1e18 precision (1e18 = no slippage).
     */
    event OTCMaxSlippageSet(address indexed exchange, uint256 maxSlippage);

    /**
     * @notice Emitted when the recharge rate for an exchange is updated.
     * @param  exchange       Address of the OTC exchange.
     * @param  normalizedRate New recharge rate in 18-decimal normalized value per second.
     */
    event OTCRechargeRateSet(address indexed exchange, uint256 normalizedRate);

    /**
     * @notice Emitted when assets are sent to an exchange for an OTC swap.
     * @param  exchange Address of the OTC exchange.
     * @param  buffer   Address of the associated buffer.
     * @param  asset    Address of the asset sent.
     * @param  amount   Amount sent in native token decimals.
     */
    event OTCSent(
        address indexed exchange,
        address indexed buffer,
        address indexed asset,
        uint256         amount
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Claims the full buffer balance of an asset back to the proxy.
     * @param  exchange Address of the OTC exchange.
     * @param  asset    Address of the asset to claim from the buffer.
     */
    function claim(address exchange, address asset) external;

    /**
     * @notice Sends assets from the proxy to the exchange for an OTC swap.
     * @param  exchange Address of the OTC exchange.
     * @param  asset    Address of the asset to send.
     * @param  amount   Amount to send in native token decimals.
     */
    function send(address exchange, address asset, uint256 amount) external;

    /**
     * @notice Sets the buffer address for an exchange.
     * @param  exchange Address of the OTC exchange.
     * @param  buffer   Address of the buffer contract.
     */
    function setBuffer(address exchange, address buffer) external;

    /**
     * @notice Sets the max slippage for an exchange.
     * @param  exchange    Address of the OTC exchange.
     * @param  maxSlippage Max slippage in 1e18 precision (1e18 = no slippage).
     */
    function setMaxSlippage(address exchange, uint256 maxSlippage) external;

    /**
     * @notice Sets the recharge rate for an exchange. Determines how quickly claim eligibility
     *        accrues over time after a send.
     * @param  exchange       Address of the OTC exchange.
     * @param  normalizedRate Recharge rate in 18-decimal normalized value per second.
     */
    function setRechargeRate(address exchange, uint256 normalizedRate) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the buffer address for an exchange.
     * @param  exchange Address of the OTC exchange.
     * @return buffer   The buffer address. Zero if not set.
     */
    function getBuffer(address exchange) external view returns (address buffer);

    /**
     * @notice Returns the current claim eligibility including time-based recharge:
     *         `normalizedClaimed + elapsed * normalizedRate`.
     * @param  exchange         Address of the OTC exchange.
     * @return claimEligibility Total claim eligibility in 18-decimal normalized value.
     */
    function getClaimWithRecharge(address exchange)
        external
        view
        returns (uint256 claimEligibility);

    /**
     * @notice Returns whether the exchange is ready for a new swap (i.e.
     *         `claim + recharge >= normalizedSent * maxSlippage / 1e18`).
     * @param  exchange Address of the OTC exchange.
     * @return isReady  True if ready for a new swap.
     */
    function getIsSwapReady(address exchange) external view returns (bool isReady);

    /**
     * @notice Returns the max slippage for an exchange.
     * @param  exchange    Address of the OTC exchange.
     * @return maxSlippage Max slippage in 1e18 precision. Zero means not set.
     */
    function getMaxSlippage(address exchange) external view returns (uint256 maxSlippage);

    /**
     * @notice Returns the recharge rate for an exchange.
     * @param  exchange       Address of the OTC exchange.
     * @return normalizedRate Recharge rate in 18-decimal normalized value per second.
     */
    function getRechargeRate(address exchange) external view returns (uint256 normalizedRate);

    /**
     * @notice Returns the current OTC swap state for an exchange.
     * @param  exchange          Address of the OTC exchange.
     * @return normalizedSent    18-decimal normalized value of the last send.
     * @return sentTimestamp     Block timestamp of the last send.
     * @return normalizedClaimed 18-decimal normalized value claimed so far.
     */
    function getState(address exchange)
        external
        view
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed);

    /**
     * @notice Returns the derived OTC send rate limit key for an exchange and asset.
     * @param  exchange Address of the OTC exchange.
     * @param  asset    Address of the asset.
     * @return key      Derived rate limit key.
     */
    function getSendRateLimitKey(address exchange, address asset)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the derived OTC claim rate limit key for an exchange and asset.
     * @param  exchange Address of the OTC exchange.
     * @param  asset    Address of the asset.
     * @return key      Derived rate limit key.
     */
    function getClaimRateLimitKey(address exchange, address asset)
        external
        pure
        returns (bytes32 key);

}
