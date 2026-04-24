// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  INFATPrimeFacet
 * @notice PAU facet for interacting with NFAT facilities on the originating (subscription) side.
 *         Exposes subscribe, withdraw, and collect flows. Rate limited per facility.
 */
interface INFATPrimeFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when capital is subscribed into an NFAT facility.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  amount       Amount of the facility's gem token subscribed (native token decimals).
     */
    event NFATSubscribe(address indexed nfatFacility, uint256 amount);

    /**
     * @notice Emitted when queued (unissued) subscribed capital is withdrawn from a facility.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  amount       Amount of the facility's gem token withdrawn (native token decimals).
     */
    event NFATWithdraw(address indexed nfatFacility, uint256 amount);

    /**
     * @notice Emitted when repaid capital is collected from an issued NFAT position.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  tokenId      Identifier of the NFAT token the collection is made against.
     * @param  amount       Amount of the facility's gem token collected (native token decimals).
     */
    event NFATCollect(address indexed nfatFacility, uint256 indexed tokenId, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Subscribes capital into an NFAT facility.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  amount       Amount of the facility's gem token to subscribe.
     * @param  data         Arbitrary subscribe payload forwarded to the facility.
     */
    function subscribe(address nfatFacility, uint256 amount, bytes calldata data) external;

    /**
     * @notice Cancels queued (unissued) subscribed capital from an NFAT facility and refills
     *         LIMIT_SUBSCRIBE by the returned amount.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  amount       Amount of the facility's gem token to withdraw.
     */
    function withdraw(address nfatFacility, uint256 amount) external;

    /**
     * @notice Collects repaid capital from an issued NFAT position, consuming LIMIT_COLLECT and
     *         refilling LIMIT_SUBSCRIBE by the collected amount.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  tokenId      Identifier of the NFAT token to collect against.
     * @param  amount       Amount of the facility's gem token to collect.
     */
    function collect(address nfatFacility, uint256 tokenId, uint256 amount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for NFAT subscribe operations, combined with the facility address to
     *         form the per-facility keys.
     */
    function LIMIT_SUBSCRIBE() external pure returns (bytes32);

    /**
     * @notice Rate limit key for NFAT collect operations, combined with the facility address to
     *         form the per-facility keys.
     */
    function LIMIT_COLLECT() external pure returns (bytes32);

}
