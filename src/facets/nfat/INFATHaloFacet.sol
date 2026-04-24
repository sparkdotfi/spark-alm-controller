// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  INFATHaloFacet
 * @notice PAU facet for repaying issued NFAT positions on an NFAT facility. Rate limited per
 *         facility and NFAT owner pair, so authorisation is expressed by setting a rate limit
 *         for the specific (facility, recipient) route.
 */
interface INFATHaloFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an issued NFAT position is repaid.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  tokenId      Identifier of the NFAT token being repaid against.
     * @param  amount       Amount of the facility's gem token repaid (native token decimals).
     */
    event NFATRepay(address indexed nfatFacility, uint256 indexed tokenId, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Repays an issued NFAT position on a facility.
     * @param  nfatFacility Address of the NFAT facility.
     * @param  tokenId      Identifier of the NFAT token being repaid against.
     * @param  amount       Amount of the facility's gem token to repay.
     */
    function repay(address nfatFacility, uint256 tokenId, uint256 amount) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for NFAT repay operations, combined with the facility and NFAT owner
     *         addresses to form the per-route keys.
     */
    function LIMIT_REPAY() external pure returns (bytes32);

}
