// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IERC721Facet
 * @notice PAU facet for transferring ERC-721 tokens out of the proxy. Restricted to admin
 *         authorisation per call rather than rate limits — see ERC721Facet.sol for rationale.
 */
interface IERC721Facet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an ERC-721 token is safe-transferred from the proxy.
     * @param  nft         Address of the ERC-721 contract.
     * @param  destination Address that received the token.
     * @param  tokenId     Identifier of the transferred token.
     */
    event ERC721SafeTransfer(
        address indexed nft,
        address indexed destination,
        uint256 indexed tokenId
    );

    /**
     * @notice Emitted when an ERC-721 token is transferred from the proxy.
     * @param  nft         Address of the ERC-721 contract.
     * @param  destination Address that received the token.
     * @param  tokenId     Identifier of the transferred token.
     */
    event ERC721Transfer(
        address indexed nft,
        address indexed destination,
        uint256 indexed tokenId
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Safe-transfers an ERC-721 token from the proxy to a destination. Use when the
     *         destination is a contract that implements IERC721Receiver.
     * @param  nft         Address of the ERC-721 contract.
     * @param  destination Address to receive the token.
     * @param  tokenId     Identifier of the token to transfer.
     */
    function safeTransfer(address nft, address destination, uint256 tokenId) external;

    /**
     * @notice Transfers an ERC-721 token from the proxy to a destination without invoking the
     *         receiver hook. Use when sending to an EOA or a contract that does not implement
     *         IERC721Receiver.
     * @param  nft         Address of the ERC-721 contract.
     * @param  destination Address to receive the token.
     * @param  tokenId     Identifier of the token to transfer.
     */
    function transfer(address nft, address destination, uint256 tokenId) external;

}
