// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IERC721Facet } from "./IERC721Facet.sol";

interface IERC721Like {

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function transferFrom(address from, address to, uint256 tokenId) external;

}

// NOTE: This facet intentionally uses DEFAULT_ADMIN_ROLE rather than RELAYER_ROLE, and has no
// rate limit. The rationale is as follows:
//
// Rate limits work well for ERC20 transfers (see TransferAssetFacet) because the `amount`
// parameter captures value — "max 1M USDC per day" is a meaningful risk bound. For ERC721,
// every call would pass amount=1 regardless of what the NFT is worth, so the limit caps
// transfer *count*, not value. A limit of "5 NFT transfers per week" provides no real
// protection if one of those NFTs represents a $10M position.
//
// Time-based refill also makes no semantic sense here. ERC20 refills are useful because
// capital is expected to cycle — you deploy, recover, and redeploy. ERC721 transfers are
// discrete, infrequent events; there is no natural reason the ability to transfer an NFT
// should automatically restore itself on a schedule without governance action.
//
// An alternative considered was a per-transfer approval pattern — governance pre-approves
// specific (nft, tokenId, destination) tuples, and the relayer executes them. This would
// provide explicit per-NFT authorisation while keeping operational speed. It was set aside
// because it requires new infrastructure not present elsewhere in this repo.
//
// DEFAULT_ADMIN_ROLE (governance) was chosen because NFT transfers are expected to be rare,
// deliberate actions. Requiring the admin to sign each transfer ensures explicit authorisation
// per transfer without needing a bespoke approval mechanism. If transfers become frequent
// enough that governance overhead is a problem, revisit the per-transfer approval pattern.
//
// Both safeTransfer and transfer are exposed: safeTransfer calls safeTransferFrom (triggers
// onERC721Received on the recipient if it is a contract) while transfer calls transferFrom
// (no callback). Use safeTransfer when the destination is a contract that implements
// IERC721Receiver; use transfer when sending to an EOA or a contract that does not implement
// the receiver hook and would otherwise reject the callback.
contract ERC721Facet is IERC721Facet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IFacet
    string public constant override VERSION = "0.1.0";

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    /// @inheritdoc IERC721Facet
    function safeTransfer(address nft, address destination, uint256 tokenId)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            nft,
            abi.encodeCall(IERC721Like.safeTransferFrom, (proxy, destination, tokenId))
        );

        emit ERC721SafeTransfer(nft, destination, tokenId);
    }

    /// @inheritdoc IERC721Facet
    function transfer(address nft, address destination, uint256 tokenId)
        external
        override
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            nft,
            abi.encodeCall(IERC721Like.transferFrom, (proxy, destination, tokenId))
        );

        emit ERC721Transfer(nft, destination, tokenId);
    }

}
