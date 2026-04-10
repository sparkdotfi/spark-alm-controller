// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

/**
 * @title  ICCTPFacet
 * @notice PAU facet for cross-chain USDC transfers via Circle's CCTP V2. Burns USDC on the source
 *         chain and mints on the destination. Large transfers are automatically split to respect
 *         per-message burn limits.
 */
interface ICCTPFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when the admin updates the max fee cap.
     * @param  maxFeeCap New upper bound on the fee for `transferWithFee`.
     */
    event CCTPMaxFeeCapSet(uint256 maxFeeCap);

    /**
     * @notice Emitted when a mint recipient is configured for a destination domain.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  mintRecipient     Bytes32-encoded address that receives minted USDC.
     */
    event CCTPMintRecipientSet(uint32 indexed destinationDomain, bytes32 indexed mintRecipient);

    /**
     * @notice Emitted per depositForBurn call for off-chain attestation tracking.
     * @dev    Used to track individual transfers for off-chain processing of CCTP transactions.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  mintRecipient     Bytes32-encoded recipient on the target chain.
     * @param  amount            Amount of USDC burned in this transfer chunk.
     */
    event CCTPTransferInitiated(
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256         amount
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Sets the maximum fee cap for `transferWithFee` calls.
     * @param  maxFeeCap Upper bound on the max fee (USDC precision, 6 decimals).
     */
    function setMaxFeeCap(uint256 maxFeeCap) external;

    /**
     * @notice Configures the mint recipient for a CCTP destination domain.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  recipient         Bytes32-encoded address to receive minted USDC.
     */
    function setMintRecipient(uint32 destinationDomain, bytes32 recipient) external;

    /**
     * @notice Transfers USDC to a destination chain via standard CCTP burn (no fee).
     * @param  amount            Amount of USDC to transfer (6-decimal precision).
     * @param  destinationDomain CCTP domain identifier for the target chain.
     */
    function transfer(uint256 amount, uint32 destinationDomain) external;

    /**
     * @notice Transfers USDC to a destination chain with a max fee for fast burns.
     * @param  amount            Amount of USDC to transfer (6-decimal precision).
     * @param  maxFee            Max fee for fast burn (USDC precision, 6 decimals).
     * @param  destinationDomain CCTP domain identifier for the target chain.
     */
    function transferWithFee(uint256 amount, uint256 maxFee, uint32 destinationDomain) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Always bytes32(0): any relayer can complete the message on the destination chain.
    function DESTINATION_CALLER() external pure returns (bytes32);

    /// @notice Rate limit key for aggregate CCTP volume across all domains.
    function LIMIT_TO_CCTP() external pure returns (bytes32);

    /**
     * @notice Rate limit key for per-domain CCTP volume, combined with the destination domain to
     *         form per-domain keys.
     */
    function LIMIT_TO_DOMAIN() external pure returns (bytes32);

    /// @notice Always zero. Standard CCTP burns do not incur a fee, so the default max fee is zero.
    function MAX_FEE() external pure returns (uint256);

    /**
     * @notice Finality threshold for CCTP depositForBurn. Value 2000 corresponds to standard
     *         (finalized) messages in CCTP V2.
     */
    function MAX_FINALITY_THRESHOLD() external pure returns (uint32);

    /// @notice Address of the CCTP TokenMessenger contract (immutable).
    function cctp() external view returns (address);

    /// @notice The configured max fee cap for `transferWithFee`.
    function maxFeeCap() external view returns (uint256);

    /// @notice Address of the USDC token contract (immutable).
    function usdc() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the configured mint recipient for a destination domain.
     * @param  destinationDomain CCTP domain identifier.
     * @return mintRecipient     Bytes32-encoded recipient. Zero if not set.
     */
    function getMintRecipient(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient);

}
