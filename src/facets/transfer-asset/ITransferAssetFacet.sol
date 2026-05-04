// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ITransferAssetFacet
 * @notice PAU facet for transferring ERC-20 assets from the proxy to a destination address. Rate
 *         limited per asset and destination pair.
 */
interface ITransferAssetFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an ERC-20 asset is transferred from the proxy.
     * @param  asset       Address of the transferred asset token.
     * @param  destination Address that received the asset.
     * @param  amount      Amount of asset transferred (native token decimals).
     */
    event TransferAssetTransfer(address indexed asset, address indexed destination, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Transfers an ERC-20 asset from the proxy to a destination.
     * @param  asset       Address of the asset token to transfer.
     * @param  destination Address to receive the asset.
     * @param  amount      Amount of asset to transfer (native token decimals).
     */
    function transfer(address asset, address destination, uint256 amount) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived transfer rate limit key for an asset and destination.
     * @param  asset       Address of the asset token.
     * @param  destination Address of the destination.
     * @return key         Derived rate limit key.
     */
    function getTransferRateLimitKey(address asset, address destination)
        external
        pure
        returns (bytes32 key);

}
