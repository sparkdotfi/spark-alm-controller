// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  INFATPrimeFacet
 * @notice PAU facet for interacting with NFAT facilities on the originating (subscription) side.
 *         Exposes subscribe, withdraw, and collect flows with per-facility rate limiting on each
 *         interaction.
 */
interface INFATPrimeFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when repaid capital is collected from an issued NFAT position.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token being collected against.
     * @param  amount   Amount of the facility's gem token collected (gem-native decimals).
     */
    event NFATPrimeCollect(address indexed facility, uint256 indexed tokenId, uint256 amount);

    /**
     * @notice Emitted when capital is subscribed into an NFAT facility.
     * @param  facility Address of the NFAT facility.
     * @param  amount   Amount of the facility's gem token subscribed (gem-native decimals).
     * @param  data     Arbitrary subscribe payload forwarded to the facility.
     */
    event NFATPrimeSubscribe(address indexed facility, uint256 amount, bytes data);

    /**
     * @notice Emitted when queued (unissued) subscribed capital is withdrawn from a facility.
     * @param  facility Address of the NFAT facility.
     * @param  amount   Amount of the facility's gem token withdrawn (gem-native decimals).
     */
    event NFATPrimeWithdraw(address indexed facility, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Collects repaid capital from an issued NFAT position, consuming the collect rate
     *         limit by the collected amount.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token to collect against.
     * @param  amount   Amount of the facility's gem token to collect. Must be non-zero.
     */
    function collect(address facility, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Subscribes capital into an NFAT facility, consuming the subscribe rate limit.
     * @dev    `amount == 0` is supported. as the facet still forwards `data` to the facility.
     * @param  facility Address of the NFAT facility.
     * @param  amount   Amount of the facility's gem token to subscribe.
     * @param  data     Arbitrary subscribe payload forwarded to the facility.
     */
    function subscribe(address facility, uint256 amount, bytes calldata data) external;

    /**
     * @notice Cancels queued (unissued) subscribed capital from an NFAT facility, consuming the
     *         withdraw rate limit by the returned amount.
     * @param  facility Address of the NFAT facility.
     * @param  amount   Amount of the facility's gem token to withdraw. Must be non-zero.
     */
    function withdraw(address facility, uint256 amount) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived collect rate limit key for an NFAT facility.
     * @param  facility Address of the NFAT facility.
     * @return key      Derived rate limit key.
     */
    function getCollectRateLimitKey(address facility) external pure returns (bytes32 key);

    /**
     * @notice Returns the derived subscribe rate limit key for an NFAT facility and gem token.
     * @dev    Keyed on `(facility, gem)` so a facility cannot change its gem under a configured
     *         rate limit; switching the gem invalidates the key.
     * @param  facility Address of the NFAT facility.
     * @param  gem      Address of the facility's gem token at configuration time.
     * @return key      Derived rate limit key.
     */
    function getSubscribeRateLimitKey(address facility, address gem)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the derived withdraw rate limit key for an NFAT facility.
     * @param  facility Address of the NFAT facility.
     * @return key      Derived rate limit key.
     */
    function getWithdrawRateLimitKey(address facility) external pure returns (bytes32 key);

}
