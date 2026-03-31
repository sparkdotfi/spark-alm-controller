// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IERC721Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function safeTransfer(address nft, address destination, uint256 tokenId) external;

    function transfer(address nft, address destination, uint256 tokenId) external;

}
