// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

/**
 * @title  ICentrifugeFacet
 * @notice PAU facet for interacting with Centrifuge V3 vaults. Supports cancel, claim-cancel,
 *         and cross-chain share transfers via Centrifuge spokes.
 */
interface ICentrifugeFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a pending deposit request is cancelled.
     * @param  token Address of the Centrifuge vault token.
     */
    event CentrifugeCancelDepositRequest(address indexed token);

    /**
     * @notice Emitted when a pending redeem request is cancelled.
     * @param  token Address of the Centrifuge vault token.
     */
    event CentrifugeCancelRedeemRequest(address indexed token);

    /**
     * @notice Emitted when assets from a cancelled deposit request are claimed.
     * @param  token Address of the Centrifuge vault token.
     */
    event CentrifugeClaimCancelDepositRequest(address indexed token);

    /**
     * @notice Emitted when shares from a cancelled redeem request are claimed.
     * @param  token Address of the Centrifuge vault token.
     */
    event CentrifugeClaimCancelRedeemRequest(address indexed token);

    /**
     * @notice Emitted when a cross-chain recipient is configured for a centrifuge ID.
     * @param  centrifugeId Centrifuge chain identifier for the destination.
     * @param  recipient    Bytes32-encoded recipient address on the destination chain.
     */
    event CentrifugeRecipientSet(uint16 indexed centrifugeId, bytes32 indexed recipient);

    /**
     * @notice Emitted when vault shares are transferred cross-chain.
     * @param  token        Address of the Centrifuge vault token.
     * @param  amount       Amount of shares transferred.
     * @param  centrifugeId Centrifuge chain identifier for the destination.
     */
    event CentrifugeTransferShares(
        address indexed token,
        uint128         amount,
        uint16  indexed centrifugeId
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Cancels a pending deposit request on a Centrifuge vault.
     * @param  token Address of the Centrifuge vault token.
     */
    function cancelDepositRequest(address token) external;

    /**
     * @notice Cancels a pending redeem request on a Centrifuge vault.
     * @param  token Address of the Centrifuge vault token.
     */
    function cancelRedeemRequest(address token) external;

    /**
     * @notice Claims assets returned from a cancelled deposit request.
     * @param  token Address of the Centrifuge vault token.
     */
    function claimCancelDepositRequest(address token) external;

    /**
     * @notice Claims shares returned from a cancelled redeem request.
     * @param  token Address of the Centrifuge vault token.
     */
    function claimCancelRedeemRequest(address token) external;

    /**
     * @notice Sets the cross-chain recipient for a given centrifuge chain ID.
     * @param  centrifugeId Centrifuge chain identifier.
     * @param  recipient    Bytes32-encoded recipient address.
     */
    function setRecipient(uint16 centrifugeId, bytes32 recipient) external;

    /**
     * @notice Transfers vault shares cross-chain via the Centrifuge spoke.
     * @notice Requires ETH for cross-chain messaging fees (payable).
     * @param  token        Address of the Centrifuge vault token.
     * @param  amount       Amount of shares to transfer.
     * @param  centrifugeId Centrifuge chain identifier for the destination.
     */
    function transferShares(address token, uint128 amount, uint16 centrifugeId) external payable;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for deposit operations, combined with the vault token address to form
     *         the per-vault keys.
     */
    function LIMIT_DEPOSIT() external pure returns (bytes32);

    /**
     * @notice Rate limit key for redeem operations, combined with the vault token address to form
     *         the per-vault keys.
     */
    function LIMIT_REDEEM() external pure returns (bytes32);

    /**
     * @notice Rate limit key for cross-chain share transfers, combined with the vault token and
     *         centrifuge ID to form the per-route keys.
     */
    function LIMIT_TRANSFER() external pure returns (bytes32);

    /**
     * @notice Always zero. Centrifuge V3 vault requests are non-fungible and use a fixed request ID
     *         of 0.
     */
    function REQUEST_ID() external pure returns (uint256);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the configured recipient for a centrifuge chain ID.
     * @param  centrifugeId Centrifuge chain identifier.
     * @return recipient    Bytes32-encoded recipient. Zero if not set.
     */
    function getRecipient(uint16 centrifugeId) external view returns (bytes32 recipient);

}
